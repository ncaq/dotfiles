-- | 呼び出す外部コマンド。
--
-- 何を呼ぶかを値として組み立ててから呼ぶので、引数の並びを実際に走らせずに検査できる。
module RemovableCrypt.Command
  ( Command (..)
  , attach
  , detach
  , mountFilesystem
  , unmountFilesystem
  , createSnapshotsSubvolume
  , createSnapshot
  , cleanupSnapshots
  ) where

import Himari
import RemovableCrypt.DeviceId (DeviceId, devicePath)
import RemovableCrypt.MapperName (MapperName, mapperNameText, mapperPath, mountPoint)
import RemovableCrypt.MountOption (MountOption, joinMountOptions)

data Command = Command
  { program :: String
  , arguments :: [String]
  }
  deriving stock (Eq, Show)

-- | 暗号化されたデバイスを復号して、マッパーの名前で見えるようにする。
--
-- 鍵の入力は`systemd-cryptsetup`が端末やFIDO2デバイスへ求める。
attach :: MapperName -> DeviceId -> Command
attach name deviceId =
  Command "systemd-cryptsetup" ["attach", convert (mapperNameText name), devicePath deviceId]

-- | 復号を解く。
detach :: MapperName -> Command
detach name = Command "systemd-cryptsetup" ["detach", convert (mapperNameText name)]

-- | 復号したデバイスをマウントポイントへマウントする。
mountFilesystem :: MapperName -> [MountOption] -> Command
mountFilesystem name options =
  Command "mount" ["-o", convert (joinMountOptions options), mapperPath name, mountPoint name]

unmountFilesystem :: MapperName -> Command
unmountFilesystem name = Command "umount" [mountPoint name]

-- | snapperがスナップショットを置くサブボリュームを作る。
createSnapshotsSubvolume :: MapperName -> Command
createSnapshotsSubvolume name =
  Command "btrfs" ["subvolume", "create", mountPoint name </> ".snapshots"]

-- | 説明を付けてスナップショットを取る。古いものはtimelineの規則で掃除される対象にする。
createSnapshot :: MapperName -> Text -> Command
createSnapshot name description =
  Command
    "snapper"
    [ "-c"
    , convert (mapperNameText name)
    , "create"
    , "--cleanup-algorithm"
    , "timeline"
    , "--description"
    , convert description
    ]

-- | timelineの規則で古いスナップショットを掃除する。
cleanupSnapshots :: MapperName -> Command
cleanupSnapshots name =
  Command "snapper" ["-c", convert (mapperNameText name), "cleanup", "timeline"]
