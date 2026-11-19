-- | `niks3`へ認証トークンを渡すための一時ファイル。
module NixCachePushNcaq.Niks3.TokenFile
  ( tokenDirectoryFrom
  , withTokenFile
  ) where

import Data.Text.IO.Utf8 (hPutStr)
import Himari
import NixCachePushNcaq.AuthToken (AuthToken (..))
import NixCachePushNcaq.Failure (ConfigFailure (..))

-- | 一時ファイルを置くtmpfsのディレクトリを選ぶ。
--
-- `XDG_RUNTIME_DIR`があればそれを使い、無ければ`/dev/shm`を使う。
-- どちらも無ければ`NoTmpfsDirectory`を投げる。
-- `/tmp`はtmpfsとは限らず、消し損ねた時に平文のトークンがディスクに残るので使わない。
tokenDirectoryFrom :: (MonadIO m, MonadThrow m) => Maybe FilePath -> m FilePath
tokenDirectoryFrom = \case
  Just directory -> pure directory
  Nothing -> do
    exists <- doesDirectoryExist sharedMemory
    unless exists (throwM NoTmpfsDirectory)
    pure sharedMemory
 where
  sharedMemory = "/dev/shm"

-- | 認証トークンを書いた一時ファイルを作って処理に渡し、処理が終わったら消す。
--
-- `niks3`は環境変数からトークンを受け取らず、引数は`/proc`から他のユーザにも見えるので、
-- `--auth-token-path`に渡すファイルを使う。
-- 環境変数と違って、`niks3`が起動する子プロセスへ引き継がれることも無い。
--
-- ファイルは所有者だけが読み書きできるモードで作られる。
-- 処理が例外で終わった時も消す。
-- SIGKILLで止められた時だけは残るので、tmpfsのディレクトリを渡すのは呼び出し側の責任である。
-- `tokenDirectoryFrom`で選べる。
--
-- 末尾に改行は付けない。
withTokenFile :: (MonadUnliftIO m) => FilePath -> AuthToken -> (FilePath -> m a) -> m a
withTokenFile directory (AuthToken token) action =
  withTempFile directory "niks3-push-ncaq-token" \path file -> do
    liftIO (hPutStr file token)
    hClose file
    action path
