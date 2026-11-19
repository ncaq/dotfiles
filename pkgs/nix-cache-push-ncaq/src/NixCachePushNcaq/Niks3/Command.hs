-- | `niks3`の呼び出し。
--
-- 呼び出しを値として持つのは、テストで実際の転送をせずに済ませるためである。
module NixCachePushNcaq.Niks3.Command
  ( Niks3 (..)
  , systemNiks3
  ) where

import Himari
import NixCachePushNcaq.Niks3.ServerUrl (ServerUrl (..))

newtype Niks3 m = Niks3
  { push :: FilePath -> ServerUrl -> [String] -> m ExitCode
  -- ^ 認証トークンを書いたファイルのパスを渡して、サーバへ転送する。残りの引数はそのまま渡す。
  }

-- | PATHにある`niks3`を呼ぶ。
systemNiks3 :: (MonadIO m) => Niks3 m
systemNiks3 =
  Niks3
    { push = \tokenFile (ServerUrl url) args ->
        runProcess
          ( proc
              "niks3"
              (["push", "--server-url", convert url, "--auth-token-path", tokenFile] <> args)
          )
    }
