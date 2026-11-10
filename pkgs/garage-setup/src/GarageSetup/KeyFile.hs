-- | キーファイルの書き出し。
module GarageSetup.KeyFile
  ( writeSecretFile
  , giveTo
  ) where

import GarageSetup.BucketName (BucketName (..))
import Himari
import System.Posix.Files (setFileMode, setOwnerAndGroup)
import System.Posix.User (getGroupEntryForName, getUserEntryForName, groupID, userID)

-- | 所有者だけが読めるファイルとして書く。
--
-- 置き場所は`RuntimeDirectory`で、systemdが他のユーザから見えないモードで作っている。
-- 書いてからモードを変えるまでの間に、他のユーザが読むことは無い。
--
-- 末尾に改行は付けない。利用する側はファイルの中身をそのままキーとして使う。
writeSecretFile :: (MonadIO m) => FilePath -> Text -> m ()
writeSecretFile path content = do
  writeBinaryFile path (convert content)
  liftIO (setFileMode path 0o400)

-- | ファイルを、名前と同じユーザとグループのものにする。
--
-- 利用するサービスのコンテナは、そのサービスと同じ名前のユーザでファイルを読む。
giveTo :: (MonadIO m) => BucketName -> FilePath -> m ()
giveTo (BucketName name) path = liftIO do
  user <- getUserEntryForName (convert name)
  groupEntry <- getGroupEntryForName (convert name)
  setOwnerAndGroup path (userID user) (groupID groupEntry)
