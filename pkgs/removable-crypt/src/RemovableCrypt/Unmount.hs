-- | `RemovableCrypt.Mount`でマウントしたデバイスをアンマウントして、復号を解く。
--
-- btrfsならアンマウントの前にsnapperでスナップショットを取る。
-- 途中の手順が失敗しても残りの手順は続ける。
-- 抜く前にできるだけ安全な状態へ近付けるためである。
module RemovableCrypt.Unmount
  ( Problem (..)
  , unmount
  ) where

import Himari
import RemovableCrypt.Command (createSnapshot, detach, unmountFilesystem)
import RemovableCrypt.Failure (Failure (..))
import RemovableCrypt.FilesystemType (FilesystemType (..))
import RemovableCrypt.MapperName (MapperName, mapperPath, mountPoint)
import RemovableCrypt.System (System (..))

-- | 失敗した手順。
data Problem
  = SnapshotFailed
  | UnmountFailed
  | RemoveMountPointFailed
  | DetachFailed
  deriving stock (Eq, Show)

-- | アンマウントして復号を解く。失敗した手順を返す。
--
-- 権限が無い時だけは何もせずに`Failure`を投げる。
unmount :: (MonadThrow m, MonadUnliftIO m) => System m -> MapperName -> m [Problem]
unmount system name = do
  controllable <- system.mapperControllable
  unless controllable (throwM NoPermission)
  catMaybes <$> sequence [snapshot, unmountDevice, removeMountPoint, detachDevice]
 where
  directory = mountPoint name
  snapshot = do
    attached <- system.pathExists (mapperPath name)
    filesystem <- if attached then system.filesystemType (mapperPath name) else pure Nothing
    if filesystem == Just Btrfs
      then SnapshotFailed `unlessSucceeds` system.execute (createSnapshot name "unmount")
      else pure Nothing
  unmountDevice = UnmountFailed `unlessSucceeds` system.execute (unmountFilesystem name)
  removeMountPoint = do
    present <- system.directoryExists directory
    if present
      then
        either (const (Just RemoveMountPointFailed)) (const Nothing)
          <$> tryAny (system.removeEmptyDirectory directory)
      else pure Nothing
  detachDevice = do
    attached <- system.pathExists (mapperPath name)
    if attached
      then DetachFailed `unlessSucceeds` system.execute (detach name)
      else pure Nothing
  unlessSucceeds problem action = (\code -> problem <$ guard (code /= ExitSuccess)) <$> action
