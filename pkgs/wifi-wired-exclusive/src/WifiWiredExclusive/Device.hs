-- | ネットワークデバイスと、`nmcli`の出力からの読み方。
module WifiWiredExclusive.Device
  ( Device (..)
  , parseDevices
  , splitFields
  ) where

import Data.Text qualified as T
import Himari hiding (try)
import Text.Megaparsec hiding (many, some)
import Text.Megaparsec.Char
import WifiWiredExclusive.DeviceName (DeviceName (..))
import WifiWiredExclusive.DeviceState (DeviceState, parseDeviceState)
import WifiWiredExclusive.DeviceType (DeviceType, parseDeviceType)

type Parser = Parsec Void Text

data Device = Device
  { name :: DeviceName
  , deviceType :: DeviceType
  , state :: DeviceState
  }
  deriving stock (Eq, Show)

-- | `nmcli -t -f DEVICE,TYPE,STATE device`の出力を読む。
--
-- 1行が`DEVICE:TYPE:STATE`の形で1つのデバイスを表す。
-- 3つの欄に分かれない行は飛ばす。
parseDevices :: Text -> [Device]
parseDevices = mapMaybe (device . splitFields) . T.lines
 where
  device = \case
    [name, deviceType, deviceState] ->
      Just
        Device
          { name = DeviceName name
          , deviceType = parseDeviceType deviceType
          , state = parseDeviceState deviceState
          }
    _ -> Nothing

-- | `nmcli`の簡潔な出力の1行を欄に分ける。
--
-- 欄は`:`で区切られていて、値の中の`:`と`\`は`\`でエスケープされている。
splitFields :: Text -> [Text]
splitFields = fromMaybe [] . parseMaybe (field `sepBy` char ':')

-- | 区切りの`:`の手前までの1つの欄。エスケープを外した値を返す。
field :: Parser Text
field = convert <$> many (try escaped <|> anySingleBut ':')
 where
  -- `\`の次の1文字は、`:`や`\`であってもそのまま値の一部になる。
  -- 行末に`\`だけが残っている時はエスケープとして読めないので、その`\`を値として読む。
  escaped = char '\\' *> anySingle
