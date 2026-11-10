-- | 外の世界への操作。
--
-- 操作を値として持つのは、テストで実際のデバイスを触らずに済ませるためである。
module RemovableCrypt.System
  ( System (..)
  , realSystem
  ) where

import Himari
import RemovableCrypt.Command (Command (..))
import RemovableCrypt.FilesystemType (FilesystemType, parseFilesystemType)
import RemovableCrypt.UserName (UserName (..))
import System.Posix.Files (fileAccess, setOwnerAndGroup)
import System.Posix.User (getUserEntryForName, userGroupID, userID)

data System m = System
  { mapperControllable :: m Bool
  -- ^ device-mapperを操作する権限があるか。
  , pathExists :: FilePath -> m Bool
  , directoryExists :: FilePath -> m Bool
  , makeDirectory :: FilePath -> m ()
  -- ^ 親も含めてディレクトリを作る。既にあれば何もしない。
  , removeEmptyDirectory :: FilePath -> m ()
  -- ^ 空のディレクトリを消す。消せなければ例外を投げる。
  , giveTo :: UserName -> FilePath -> m ()
  -- ^ パスを、ユーザとそのログイングループのものにする。
  , filesystemType :: FilePath -> m (Maybe FilesystemType)
  -- ^ デバイスの中のファイルシステムの種類を調べる。調べられなければ`Nothing`。
  , execute :: Command -> m ExitCode
  }

-- | 実際のシステムを操作する。外部コマンドはPATHから探す。
realSystem :: (MonadUnliftIO m) => System m
realSystem =
  System
    { mapperControllable =
        -- 無い時は例外になるので、権限が無いのと同じに扱う。
        fromRight False
          <$> tryIO (liftIO (fileAccess "/dev/mapper/control" False True False))
    , pathExists = doesPathExist
    , directoryExists = doesDirectoryExist
    , makeDirectory = createDirectoryIfMissing True
    , removeEmptyDirectory = removeDirectory
    , giveTo = \(UserName name) path -> liftIO do
        user <- getUserEntryForName (convert name)
        setOwnerAndGroup path (userID user) (userGroupID user)
    , filesystemType = \device -> do
        (code, output) <- readProcessStdout (proc "blkid" ["-s", "TYPE", "-o", "value", device])
        pure (parseFilesystemType (convert output) <$ guard (code == ExitSuccess))
    , execute = \command -> runProcess (proc command.program command.arguments)
    }
