-- | 転送するコマンドの子プロセスの起動。
module NixCachePushNcaq.Process
  ( runWithVariable
  ) where

import Himari
import System.Process.Typed qualified

-- | 環境変数を1つ足して子プロセスを実行し、終了コードを返す。
--
-- 復号したトークンをファイルにも引数にも書かずに渡すために使う。
-- 引数は`/proc`から他のユーザにも見える。
-- 他の環境変数と標準入出力はこのプロセスのものを引き継ぐ。
runWithVariable :: (MonadIO m) => String -> String -> ProcessConfig i o e -> m ExitCode
runWithVariable name value config = do
  inherited <- getEnvironment
  runProcess
    (System.Process.Typed.setEnv ((name, value) : filter ((/= name) . fst) inherited) config)
