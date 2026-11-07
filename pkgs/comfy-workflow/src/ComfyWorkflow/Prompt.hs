-- | API形式のプロンプトの手直しと、実行結果の読み取り。
--
-- 公式の`comfy run --print-prompt`が組み立てたAPI形式を、
-- そのまま`POST /prompt`へ投げられる形に直す。
-- 直すのはカスタムノードのJavaScript拡張が描くウィジェットで、
-- `/object_info`には現れないのに`widgets_values`の位置を占めるものである。
-- 公式の変換はノード定義から導けないものを落とすので、
-- 必須の入力が欠けてサーバに弾かれる。
-- ここへ書き写すしかない。
--
-- 結果の読み取りは`/history/<prompt_id>`の応答から、
-- 保存されたファイルのパスを集める。
module ComfyWorkflow.Prompt
  ( Prompt
  , fixupPrompt
  , frontendWidgets
  , HistoryResult (..)
  , readHistory
  , relativeOutput
  , asObject
  , jsonText
  ) where

import ComfyWorkflow.Workflow (Node (..))
import Himari

-- | JSONの値を利用者に見せる文字列にする。
--
-- `show`はaesonの構築子を含むHaskellの表現を出し、
-- 非ASCII文字を`\12354`のように10進のエスケープへ変えるので、
-- 日本語のプロンプトやファイル名が読めなくなる。
-- JSONとして出せばUTF-8のまま残る。
jsonText :: Value -> Text
jsonText = convert . encode

-- | フロントエンドの拡張が描くウィジェット。
--
-- ノード型ごとに、
-- `widgets_values`の何番目をどの入力名で送るかと、
-- 公式の変換が代わりに作ってしまう余計な入力名を持つ。
frontendWidgets :: [(Text, ([(Int, Text)], [Text]))]
frontendWidgets =
  [ -- LoRA Managerの`Lora Loader (LoraManager)`。
    -- `text`は`AUTOCOMPLETE_TEXT_LORAS`という拡張だけが知る型で、
    -- 先頭がテキスト補完のメタデータ、末尾が適用中のLoRAの一覧。
    -- ノード定義が持つのは真ん中の`text`だけである。
    -- 公式の変換は空文字列の値から`➕ Add Lora`という入力を作るが、
    -- これは別のLoRAノードのボタンを見込んだ規則で、ここでは要らない。
    ("Lora Loader (LoraManager)", ([(1, "text")], ["➕ Add Lora"]))
  ]

-- | API形式のプロンプト。ノードIDからノードの辞書への辞書。
--
-- aesonの`Object`ではなく`Map`で持つ。
-- lensで出し入れできるのが`Map`の方だからで、
-- JSONとの行き来はaesonのインスタンスがそのまま面倒を見る。
type Prompt = Map Text Value

-- | API形式のプロンプトを手直しする。
--
-- 既に入力があるものは触らない。
-- 公式の変換が対応した時にここが何もしなくなるようにするためである。
fixupPrompt :: [Node] -> Prompt -> Prompt
fixupPrompt nodes = imap fixupNode
 where
  fixupNode key apiNodeValue
    | Just node <- find (\node -> node.nodeId == key) nodes
    , Just (fills, spurious) <- lookup node.nodeType frontendWidgets
    , Just apiNode <- asObject apiNodeValue
    , Just inputs <- apiNode ^. at "inputs" >>= asObject =
        let cleaned = foldl' (\object name -> object & at name .~ Nothing) inputs spurious
            filled = foldl' (fill node) cleaned fills
         in toJSON (apiNode & at "inputs" ?~ toJSON filled)
  fixupNode _ value = value
  fill node inputs (position, name)
    | has (ix name) inputs = inputs
    | Just value <- node.widgetsValues ^? ix position = inputs & at name ?~ value
    | otherwise = inputs

data HistoryResult
  = -- | 保存されたファイルの、出力ディレクトリからの相対パス。
    Succeeded [FilePath]
  | Failed Text
  deriving stock (Eq, Show)

-- | `/history/<prompt_id>`の応答から結果を読む。
--
-- ComfyUIはノードの実行エラーでも履歴を作る。
-- 見ないと出力が空のまま成功したように見えて、
-- 成功したが出力が0件の場合と区別が付かない。
--
-- `status`が読めない時は失敗と報告しない。
-- 上流が形を変えた時に、
-- 成功した生成が失敗するようになる方が困る。
readHistory :: Text -> Value -> Either Text HistoryResult
readHistory promptId history = do
  entry <-
    maybe (Left ("履歴に" <> promptId <> "がありません")) Right $
      asObject history >>= (^. at promptId) >>= asObject
  let status = entry ^. at "status" >>= asObject
      statusStr = status >>= (^. at "status_str") >>= asText
  case statusStr of
    Just str
      | str /= "success" ->
          -- どのノードで何が起きたのかは`messages`にしか無い。
          let messages = maybe "" jsonText (status >>= (^. at "messages"))
           in pure (Failed (str <> ": " <> messages))
    _ -> Succeeded <$> collectOutputs entry

-- | 履歴1件から、保存されたファイルのパスを集める。
--
-- 保存ノードの種類ごとに`images`や`gifs`のようにキーが違うので、
-- キーを決め打ちせずに`filename`を持つものを拾う。
-- 入力として置き直しただけのものは`type`が`output`にならないので外す。
collectOutputs :: Map Text Value -> Either Text [FilePath]
collectOutputs entry =
  traverse
    toPath
    [ item
    | nodeOutput <- foldMap toList (entry ^. at "outputs" >>= asObject)
    , values <- foldMap toList (asObject nodeOutput)
    , Array items <- [values]
    , item <- mapMaybe asObject (toList items)
    , (item ^. at "type" >>= asText) == Just "output"
    , isJust (item ^. at "filename" >>= asText)
    ]
 where
  toPath item =
    relativeOutput
      (fromMaybe "" (item ^. at "subfolder" >>= asText))
      (fromMaybe "" (item ^. at "filename" >>= asText))

-- | 出力ディレクトリからの相対パスとして安全な形だけを返す。
--
-- サーバの応答をそのまま出力ディレクトリへ連結すると、
-- `filename`が絶対パスだった場合に左辺が捨てられて、
-- 出力先の外のパスがそこに保存されたかのように表示される。
-- `subfolder`に`..`が入っても同じである。
--
-- 弾くのは経路としての`..`だけにする。
-- `a..b.png`のように名前の一部として現れる`..`まで弾くと、
-- 普通に保存できるファイルが表示できなくなる。
relativeOutput :: Text -> Text -> Either Text FilePath
relativeOutput subfolder filename
  | isAbsolute path || ".." `elem` splitDirectories path =
      Left ("出力先の外を指すパスが返りました: " <> subfolder <> "/" <> filename)
  | otherwise = Right path
 where
  path =
    if subfolder == ""
      then convert filename
      else convert subfolder </> convert filename

-- | JSONのオブジェクトだけを`Map`として取り出す。
asObject :: Value -> Maybe (Map Text Value)
asObject value = case fromJSON value of
  Success object -> Just object
  Error _ -> Nothing

asText :: Value -> Maybe Text
asText (String t) = Just t
asText _ = Nothing
