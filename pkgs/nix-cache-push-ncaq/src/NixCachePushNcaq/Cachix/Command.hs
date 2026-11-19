-- | `cachix`の呼び出し。
--
-- 呼び出しを値として持つのは、テストで実際の転送をせずに済ませるためである。
module NixCachePushNcaq.Cachix.Command
  ( Cachix (..)
  , systemCachix
  ) where

import Himari
import NixCachePushNcaq.AuthToken (AuthToken (..))
import NixCachePushNcaq.Cachix.CacheName (CacheName (..))
import NixCachePushNcaq.Process (runWithVariable)

newtype Cachix m = Cachix
  { push :: AuthToken -> CacheName -> [String] -> m ExitCode
  -- ^ 認証トークンを渡して、キャッシュへ転送する。残りの引数はそのまま渡す。
  }

-- | PATHにある`cachix`を呼ぶ。
--
-- 引数が無い時は`cachix`が標準入力からstoreパスの一覧を読む。
systemCachix :: (MonadIO m) => Cachix m
systemCachix =
  Cachix
    { push = \(AuthToken token) (CacheName cache) args ->
        runWithVariable
          "CACHIX_AUTH_TOKEN"
          (convert token)
          (proc "cachix" (["push", convert cache] <> args))
    }
