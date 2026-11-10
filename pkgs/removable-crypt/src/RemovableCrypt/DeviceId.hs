-- | `/dev/disk/by-id/`以下の、暗号化されたデバイスのID。
module RemovableCrypt.DeviceId
  ( DeviceId
  , parseDeviceId
  , devicePath
  ) where

import Himari
import RemovableCrypt.DeviceMapperName (validDeviceMapperName)

-- | 検査を通ったID。
newtype DeviceId = DeviceId Text
  deriving stock (Eq, Show)

-- | マッパーの名前と同じ規則で検査する。
--
-- udevが作るIDはこの範囲に収まる。
parseDeviceId :: Text -> Maybe DeviceId
parseDeviceId deviceId = DeviceId deviceId <$ guard (validDeviceMapperName deviceId)

-- | 暗号化されたデバイスのパス。
devicePath :: DeviceId -> FilePath
devicePath (DeviceId deviceId) = "/dev/disk/by-id" </> convert deviceId
