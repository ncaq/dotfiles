-- | `niks3`へ認証トークンを渡すための一時ファイル。
module NixCachePushNcaq.Niks3.TokenFile
  ( withTokenFile
  ) where

import Data.Text.IO.Utf8 (hPutStr)
import Himari
import NixCachePushNcaq.AuthToken (AuthToken (..))

-- | 認証トークンを書いた一時ファイルを作って処理に渡し、処理が終わったら消す。
--
-- `niks3`は環境変数からトークンを受け取らず、引数は`/proc`から他のユーザにも見えるので、
-- `--auth-token-path`に渡すファイルを使う。
-- 環境変数と違って、`niks3`が起動する子プロセスへ引き継がれることも無い。
--
-- ファイルは所有者だけが読み書きできるモードで作られる。
-- 処理が例外で終わった時も消す。
-- SIGKILLで止められた時だけは残るので、ディレクトリにはtmpfsを選ぶ。
--
-- 末尾に改行は付けない。
withTokenFile :: (MonadUnliftIO m) => FilePath -> AuthToken -> (FilePath -> m a) -> m a
withTokenFile directory (AuthToken token) action =
  withTempFile directory "niks3-push-ncaq-token" \path file -> do
    liftIO (hPutStr file token)
    hClose file
    action path
