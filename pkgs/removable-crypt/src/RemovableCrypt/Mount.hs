-- | 暗号化されたリムーバブルデバイスを復号してマウントする。
--
-- btrfsならマウント後にsnapperでスナップショットを取り、古いものを掃除する。
-- 途中で失敗した時は、そこまでに行ったマウントと復号を巻き戻す。
module RemovableCrypt.Mount
  ( MountRequest (..)
  , mount
  ) where

import Himari
import RemovableCrypt.Command
  ( attach
  , cleanupSnapshots
  , createSnapshot
  , createSnapshotsSubvolume
  , detach
  , mountFilesystem
  , unmountFilesystem
  )
import RemovableCrypt.DeviceId (DeviceId, devicePath)
import RemovableCrypt.Failure (Failure (..))
import RemovableCrypt.FilesystemType (FilesystemType (..))
import RemovableCrypt.MapperName (MapperName, mapperPath, mountPoint)
import RemovableCrypt.MountOption (MountOption)
import RemovableCrypt.System (System (..))
import RemovableCrypt.UserName (UserName)

data MountRequest = MountRequest
  { name :: MapperName
  , deviceId :: DeviceId
  , mountOptions :: [MountOption]
  -- ^ 全てのファイルシステムで使うマウントオプション。
  , btrfsMountOptions :: [MountOption]
  -- ^ btrfsの時に`mountOptions`へ足すマウントオプション。
  , owner :: UserName
  -- ^ マウントポイントの所有者にするユーザ。
  }
  deriving stock (Eq, Show)

-- | 復号してマウントする。失敗したら巻き戻して`Failure`を投げる。
mount :: (MonadThrow m, MonadUnliftIO m) => System m -> MountRequest -> m ()
mount system request = do
  controllable <- system.mapperControllable
  unless controllable (throwM NoPermission)
  deviceExists <- system.pathExists (devicePath request.deviceId)
  unless deviceExists (throwM (DeviceNotFound (devicePath request.deviceId)))
  run (attach request.name request.deviceId)
  mountAttached `onException` do
    removeMountPoint
    quietly (detach request.name)
 where
  directory = mountPoint request.name
  -- 復号した後の手順。ここで失敗したら、呼び出し側がマウントポイントと復号を片付ける。
  mountAttached = do
    system.makeDirectory directory
    system.giveTo request.owner directory
    filesystem <-
      system.filesystemType (mapperPath request.name)
        >>= maybe (throwM (UnknownFilesystem (mapperPath request.name))) pure
    run . mountFilesystem request.name $ case filesystem of
      Btrfs -> request.mountOptions <> request.btrfsMountOptions
      OtherFilesystem _ -> request.mountOptions
    afterMount filesystem `onException` quietly (unmountFilesystem request.name)
  -- マウントした後の手順。ここで失敗したら、アンマウントしてから上の片付けへ進む。
  afterMount filesystem = do
    -- マウントするとマウントポイントはファイルシステムのルートになるので、所有者を付け直す。
    system.giveTo request.owner directory
    when (filesystem == Btrfs) do
      hasSnapshots <- system.directoryExists (directory </> ".snapshots")
      unless hasSnapshots (run (createSnapshotsSubvolume request.name))
      run (createSnapshot request.name "mount")
      run (cleanupSnapshots request.name)
  -- 失敗したら`Failure`として投げる。
  run command =
    system.execute command >>= \case
      ExitSuccess -> pure ()
      code -> throwM (CommandFailed command code)
  -- 片付けの中の失敗は無視する。元の失敗を上へ伝える方を優先する。
  quietly = void . system.execute
  removeMountPoint = do
    present <- system.directoryExists directory
    when present (void (tryAny (system.removeEmptyDirectory directory)))
