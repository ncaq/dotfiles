-- | App Modeの入力定義と`comfy workflow slots`の一覧から、
-- コマンドラインのパラメータを決める。
--
-- 「どれが入力か」はApp Modeの定義が宣言していて、
-- 「その型と選択肢は何か」はスロットの一覧が知っている。
-- アドレス`<ノードID>.<ウィジェット名>`で両者を突き合わせる。
--
-- seedはパラメータにしない。
-- UIで`randomize`にしてあるseedを振り直しているのはフロントエンドなので、
-- APIから投げると書かれた値のまま固まる。
-- サンプラーが複数あるワークフローではその全てを揃って動かしたいので、
-- 1つのノードを指すフラグではなく全体の`--seed`へ寄せる。
module ComfyWorkflow.Parameter
  ( Parameter (..)
  , parameters
  , reservedFlags
  , seedWidgetNames
  , parseValue
  , positiveInt
  ) where

import ComfyWorkflow.Name (candidates, resolveNames)
import ComfyWorkflow.Slot (Slot (..), WidgetType (..))
import ComfyWorkflow.Workflow (AppInput (..), Node (..), Workflow (..))
import Data.Text (intercalate, toLower)
import Himari

data Parameter = Parameter
  { flag :: Text
  -- ^ フラグ名。先頭の`--`は含まない。
  , slot :: Slot
  , description :: Maybe Text
  -- ^ `--help`へ出す説明。App Modeの入力定義が持っていれば使う。
  }
  deriving stock (Eq, Show)

-- | 全体のオプションが使う名前。パラメータ側には譲らせる。
reservedFlags :: [Text]
reservedFlags = ["help", "seed", "repeat", "dry-run", "no-wait"]

-- | フロントエンドが実行後の振る舞いを付けるseedのウィジェット名。
seedWidgetNames :: [Text]
seedWidgetNames = ["seed", "noise_seed"]

parameters :: Workflow -> [Slot] -> Either Text [Parameter]
parameters workflow slots = do
  entries <- traverse resolveEntry (filter (not . isSeedInput) workflow.appInputs)
  let names = resolveNames reservedFlags (fmap candidatesOf entries)
  pure
    [ Parameter{flag, slot, description = input.description}
    | (flag, (input, _, slot)) <- zip names entries
    ]
 where
  isSeedInput input = input.widget `elem` seedWidgetNames
  resolveEntry input = do
    node <-
      maybe
        (Left ("App Mode入力が存在しないノード" <> input.nodeId <> "を指しています"))
        Right
        (find (\node -> node.nodeId == input.nodeId) workflow.nodes)
    slot <-
      maybe
        (Left ("ノード" <> input.nodeId <> "(" <> node.nodeType <> ")に" <> input.widget <> "がありません"))
        Right
        (find (\slot -> slot.address == input.nodeId <> "." <> input.widget) slots)
    pure (input, node, slot)
  candidatesOf (input, node, _) = candidates input.nodeId (fromMaybe "" node.title) input.widget

-- | コマンドラインの文字列をウィジェットの型へ直す。
parseValue :: WidgetType -> Text -> Either Text Value
parseValue IntWidget text = case readMay (convert text) of
  Just (integer :: Integer) -> Right (toJSON integer)
  Nothing -> Left ("整数として読めません: " <> text)
-- Haskellの`Read`の書き方に従うので、`.5`や`5.`や`+5`は受け付けない。
-- `NaN`と`Infinity`は`Read`では読めてしまうが、
-- JSONには表せず`toJSON`で`null`になるので、ここで弾く。
parseValue FloatWidget text = case readMay (convert text) of
  Just (double :: Double)
    | isNaN double || isInfinite double -> Left ("有限の数値ではありません: " <> text)
    | otherwise -> Right (toJSON double)
  Nothing -> Left ("数値として読めません: " <> text)
parseValue BooleanWidget text
  | lowered `elem` ["true", "1", "yes", "on"] = Right (Bool True)
  | lowered `elem` ["false", "0", "no", "off"] = Right (Bool False)
  | otherwise = Left ("真偽値として読めません: " <> text)
 where
  lowered = toLower text
parseValue (ComboWidget choices) text
  | not (null choices) && text `notElem` choices =
      Left ("選べるのは" <> summarizeChoices choices <> "のいずれかです")
  | otherwise = Right (String text)
parseValue StringWidget text = Right (String text)
parseValue (OtherWidget _) text = Right (String text)

-- | エラーに出す選択肢の一覧。
--
-- 画像を選ぶウィジェットは入力ディレクトリの全ファイルが選択肢になるので、
-- 数百件を全部並べると肝心のメッセージが埋もれる。
-- 全部を見たければ`--help`に出る。
summarizeChoices :: [Text] -> Text
summarizeChoices choices
  | length choices <= limit = intercalate ", " choices
  | otherwise =
      intercalate ", " (take limit choices)
        <> " ほか"
        <> convert (show (length choices - limit))
        <> "件(全ては--helpを参照)"
 where
  limit = 20

-- | `--repeat`が受け付ける値へ直す。
--
-- 0以下を通すと何も投げずに、何のメッセージも出さずに正常終了する。
-- 利用者から見ると成功したのに結果が出ない状態と区別が付かない。
positiveInt :: String -> Either String Int
positiveInt text = case readMay text of
  Just value
    | value >= 1 -> Right value
    | otherwise -> Left ("1以上が要ります: " <> text)
  Nothing -> Left ("整数として読めません: " <> text)
