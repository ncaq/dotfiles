-- | `sops`の呼び出し。
--
-- 呼び出しを値として持つのは、テストで実際の復号をせずに済ませるためである。
module NixCachePushNcaq.Sops
  ( Sops (..)
  , systemSops
  ) where

import Himari
import NixCachePushNcaq.AuthToken (AuthToken, authTokenFromOutput)
import NixCachePushNcaq.Failure (SecretsFailure (..))
import NixCachePushNcaq.SecretKey (SecretKey (..))

newtype Sops m = Sops
  { extract :: SecretKey -> FilePath -> m AuthToken
  -- ^ シークレットファイルから、キーの指す認証トークンを復号する。失敗したら例外を投げる。
  }

-- | PATHにある`sops`を呼ぶ。
--
-- 復号したトークンはファイルに書かず、標準出力から受け取る。
systemSops :: (MonadIO m, MonadThrow m) => Sops m
systemSops =
  Sops
    { extract = \(SecretKey key) path -> do
        (code, output) <-
          readProcessStdout
            (proc "sops" ["decrypt", "--extract", convert ("[\"" <> key <> "\"]"), path])
        unless (code == ExitSuccess) (throwM (DecryptFailed path code))
        authTokenFromOutput output
    }
