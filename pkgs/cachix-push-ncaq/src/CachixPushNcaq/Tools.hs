-- | `sops`と`cachix`の呼び出し。
--
-- 呼び出しを値として持つのは、テストで実際の復号や転送をせずに済ませるためである。
module CachixPushNcaq.Tools
  ( Tools (..)
  , systemTools
  ) where

import CachixPushNcaq.AuthToken (AuthToken (..), authTokenFromOutput)
import CachixPushNcaq.CacheName (CacheName (..))
import CachixPushNcaq.Failure (SecretsFailure (..))
import Himari
import System.Process.Typed qualified

data Tools m = Tools
  { decrypt :: FilePath -> m AuthToken
  -- ^ シークレットファイルから認証トークンを復号する。失敗したら例外を投げる。
  , push :: AuthToken -> CacheName -> [String] -> m ExitCode
  -- ^ 認証トークンを渡して、キャッシュへ転送する。残りの引数はそのまま渡す。
  }

-- | PATHにある`sops`と`cachix`を呼ぶ。
systemTools :: (MonadIO m, MonadThrow m) => Tools m
systemTools =
  Tools
    { decrypt = \path -> do
        (code, output) <-
          readProcessStdout (proc "sops" ["decrypt", "--extract", "[\"CACHIX_AUTH_TOKEN\"]", path])
        unless (code == ExitSuccess) (throwM (DecryptFailed path code))
        authTokenFromOutput output
    , push = \(AuthToken token) (CacheName cache) args -> do
        inherited <- getEnvironment
        -- 復号したトークンはファイルに書かず、環境変数で`cachix`へ渡す。
        -- 引数が無い時に`cachix`がstoreパスの一覧を読めるように、標準入力は引き継ぐ。
        runProcess
          . System.Process.Typed.setEnv
            ((tokenVariable, convert token) : filter ((/= tokenVariable) . fst) inherited)
          $ proc "cachix" (["push", convert cache] <> args)
    }
 where
  tokenVariable = "CACHIX_AUTH_TOKEN"
