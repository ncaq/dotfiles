-- | UI形式のワークフローから、このコマンドが見る部分だけを取り出す。
--
-- 見るのは2つである。
--
-- * ノードの一覧。
--   ノードIDとノード型とタイトルと、`widgets_values`の値の並び。
--   タイトルはフラグ名の候補に、
--   `widgets_values`はseedの振り直しの約束を読むのに使う。
-- * `extra.linearData.inputs`。
--   ComfyUIのApp Modeが画面へ並べる入力の定義で、
--   そのワークフローで人が触る値だけを`[ノードID, ウィジェット名]`で列挙している。
--   これをそのままコマンドラインのフラグにする。
--
-- UI形式からAPI形式への変換はここではやらない。
-- 公式の`comfy run`がやるので、
-- ここが`widgets_values`の何番目が何かを知る必要は無い。
module ComfyWorkflow.Workflow
  ( Workflow (..)
  , Node (..)
  , AppInput (..)
  , NodeId (..)
  , parseWorkflow
  ) where

import Himari

data Node = Node
  { nodeId :: Text
  , nodeType :: Text
  , title :: Maybe Text
  , widgetsValues :: [Value]
  }
  deriving stock (Eq, Show)

data AppInput = AppInput
  { nodeId :: Text
  , widget :: Text
  , description :: Maybe Text
  }
  deriving stock (Eq, Show)

data Workflow = Workflow
  { nodes :: [Node]
  , appInputs :: [AppInput]
  }
  deriving stock (Eq, Show)

parseWorkflow :: Value -> Either Text Workflow
parseWorkflow value = case fromJSON value of
  Success workflow -> Right workflow
  Error reason -> Left (convert reason)

instance FromJSON Workflow where
  parseJSON = withObject "ワークフロー" \o -> do
    nodes <- o .: "nodes"
    extra :: Object <- o .:? "extra" .!= mempty
    linear :: Object <- extra .:? "linearData" .!= mempty
    appInputs <- linear .:? "inputs" .!= []
    pure Workflow{..}

instance FromJSON Node where
  parseJSON = withObject "ノード" \o -> do
    NodeId nodeId <- o .: "id"
    nodeType <- o .: "type"
    title <- o .:? "title"
    -- `widgets_values`はウィジェットを持たないノードでは省かれる。
    -- 配列ではなく辞書で書かれる形式もあるが、
    -- その形で書かれたノードのseedを振り直す用途は無いので値の並びが無いものとして扱う。
    widgetsRaw <- o .:? "widgets_values" .!= Null
    let widgetsValues = case widgetsRaw of
          Array values -> toList values
          _ -> []
    pure Node{..}

-- | App Modeの入力定義1つ。
-- `[ノードID, ウィジェット名]`か`[ノードID, ウィジェット名, 設定]`の形で書かれている。
instance FromJSON AppInput where
  parseJSON = withArray "App Mode入力" \entry -> case toList entry of
    (rawId : rawWidget : rest) -> do
      NodeId nodeId <- parseJSON rawId
      widget <- parseJSON rawWidget
      description <- case rest of
        (config : _) -> withObject "App Mode入力の設定" (.:? "description") config
        [] -> pure Nothing
      pure AppInput{..}
    _ -> fail "App Mode入力はノードIDとウィジェット名の並びです"

-- | 文字列へ揃えたノードID。
--
-- UI形式のノードIDは数値だが、
-- API形式の辞書のキーと`comfy workflow slots`のアドレスは文字列で、
-- 突き合わせる相手が全て文字列なのでこちらも文字列で持つ。
newtype NodeId = NodeId Text
  deriving stock (Eq, Show)

instance FromJSON NodeId where
  parseJSON (String text) = pure (NodeId text)
  parseJSON value@(Number _) = do
    -- 整数でない数値は`Integer`として読めないので、ここで弾かれる。
    integer :: Integer <- parseJSON value
    pure (NodeId (convert (show integer)))
  parseJSON _ = fail "ノードIDが数値でも文字列でもありません"
