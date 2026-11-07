-- | `comfy workflow slots`が返す、ワークフローのウィジェットの一覧。
--
-- 公式CLIはウィジェットを`<ノードID>.<入力名>`のアドレスで指す。
-- 型と選択肢と現在の値も一緒に返すので、
-- `--help`に出す情報と値の解釈の規則はここから取れる。
-- `/object_info`を自分で読んで`widgets_values`の位置合わせをする必要は無い。
--
-- 公式CLIの出力は`envelope/1`という封筒に包まれていて、
-- 成功でも失敗でも同じ形で返る。
-- 失敗の時は`error`に理由が入る。
module ComfyWorkflow.Slot
  ( Slot (..)
  , WidgetType (..)
  , Slots (..)
  , Envelope (..)
  , ComfyError (..)
  , describeError
  ) where

import Himari

data WidgetType
  = IntWidget
  | FloatWidget
  | BooleanWidget
  | -- | 選択肢。`enum`が付かない`COMBO`もあるので空になりうる。
    ComboWidget [Text]
  | StringWidget
  | -- | 上のどれでもないもの。値はそのまま文字列として渡す。
    OtherWidget Text
  deriving stock (Eq, Show)

data Slot = Slot
  { address :: Text
  , name :: Text
  , instanceId :: Text
  , nodeType :: Text
  , widgetType :: WidgetType
  , currentValue :: Value
  }
  deriving stock (Eq, Show)

instance FromJSON Slot where
  parseJSON = withObject "スロット" \o -> do
    address <- o .: "address"
    name <- o .: "name"
    instanceId <- o .: "instance_id"
    nodeType <- o .: "node_type"
    kind <- o .: "type"
    choices <- o .:? "enum" .!= []
    currentValue <- o .:? "current_value" .!= Null
    let widgetType = case kind :: Text of
          "INT" -> IntWidget
          "FLOAT" -> FloatWidget
          "BOOLEAN" -> BooleanWidget
          "COMBO" -> ComboWidget choices
          "STRING" -> StringWidget
          other -> OtherWidget other
    pure Slot{..}

newtype Slots = Slots [Slot]
  deriving stock (Eq, Show)

instance FromJSON Slots where
  parseJSON = withObject "スロットの一覧" \o -> Slots <$> o .: "slots"

data ComfyError = ComfyError
  { code :: Text
  , message :: Text
  , hint :: Maybe Text
  }
  deriving stock (Eq, Show)

instance FromJSON ComfyError where
  parseJSON = withObject "公式CLIのエラー" \o -> do
    code <- o .: "code"
    message <- o .: "message"
    hint <- o .:? "hint"
    pure ComfyError{..}

-- | 公式CLIの`--json`が返す封筒。
data Envelope a = Envelope
  { ok :: Bool
  , payload :: Maybe a
  , failure :: Maybe ComfyError
  }
  deriving stock (Eq, Show)

instance (FromJSON a) => FromJSON (Envelope a) where
  parseJSON = withObject "公式CLIの封筒" \o -> do
    ok <- o .: "ok"
    payload <- o .:? "data"
    failure <- o .:? "error"
    pure Envelope{..}

describeError :: ComfyError -> Text
describeError err = err.message <> " (" <> err.code <> ")" <> maybe "" ("\n" <>) err.hint
