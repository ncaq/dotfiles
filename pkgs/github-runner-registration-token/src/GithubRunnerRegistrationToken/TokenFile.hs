-- | 登録トークンのファイルへの書き出し。
module GithubRunnerRegistrationToken.TokenFile
  ( tokenFileName
  , writeTokenFile
  ) where

import GithubRunnerRegistrationToken.RegistrationToken (RegistrationToken (..))
import Himari
import System.Posix.Files (setFileMode)

-- | `RUNTIME_DIRECTORY`の中での登録トークンのファイルの名前。
tokenFileName :: FilePath
tokenFileName = "token"

-- | 所有者だけが読めるファイルとして、前のトークンと置き換える。
--
-- ランナーは登録し直すたびにこのファイルを読む。
-- 書きかけの中身を読まれないように、同じディレクトリに書いてからrenameで置き換える。
--
-- 置き場所は`RuntimeDirectory`で、systemdが他のユーザから見えないモードで作っている。
-- 置き換えてからモードを変えるまでの間に、他のユーザが読むことは無い。
--
-- 末尾に改行は付けない。ランナーの側はファイルの中身をそのままトークンとして使う。
writeTokenFile :: (MonadIO m) => FilePath -> RegistrationToken -> m ()
writeTokenFile path (RegistrationToken token) = do
  writeBinaryFileAtomic path (convert token)
  liftIO (setFileMode path 0o400)
