-- | 復号したデバイスに付ける、device-mapperの名前。
--
-- マウントポイントとsnapperの設定の名前も兼ねる。
module RemovableCrypt.MapperName
  ( MapperName
  , parseMapperName
  , mapperNameText
  , mapperPath
  , mountPoint
  ) where

import Himari
import RemovableCrypt.DeviceMapperName (validDeviceMapperName)

-- | 検査を通った名前。
newtype MapperName = MapperName Text
  deriving stock (Eq, Show)

parseMapperName :: Text -> Maybe MapperName
parseMapperName name = MapperName name <$ guard (validDeviceMapperName name)

mapperNameText :: MapperName -> Text
mapperNameText (MapperName name) = name

-- | 復号したデバイスのパス。
mapperPath :: MapperName -> FilePath
mapperPath (MapperName name) = "/dev/mapper" </> convert name

-- | マウントする場所。
mountPoint :: MapperName -> FilePath
mountPoint (MapperName name) = "/mnt" </> convert name
