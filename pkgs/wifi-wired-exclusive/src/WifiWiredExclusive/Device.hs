-- | ネットワークデバイスと、`nmcli`の出力からの読み方。
module WifiWiredExclusive.Device
  ( Device (..)
  , parseDevices
  , splitFields
  ) where

import Data.Text qualified as T
import Himari
import WifiWiredExclusive.DeviceName (DeviceName (..))
import WifiWiredExclusive.DeviceState (DeviceState, parseDeviceState)
import WifiWiredExclusive.DeviceType (DeviceType, parseDeviceType)

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
splitFields = fmap convert . go "" . convert
 where
  go :: String -> String -> [String]
  go field = \case
    [] -> [reverse field]
    '\\' : character : rest -> go (character : field) rest
    ':' : rest -> reverse field : go "" rest
    character : rest -> go (character : field) rest
