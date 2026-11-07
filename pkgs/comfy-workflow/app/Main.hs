module Main (main) where

import ComfyWorkflow.Cli (run)
import ComfyWorkflow.Comfy (ComfyFailure (..))
import Himari

main :: IO ()
main = do
  args <- getArgs
  -- 普段は進捗だけを見せる。
  -- 公式CLIに何をどう渡したかは、`COMFY_WORKFLOW_DEBUG`を立てた時だけ出す。
  debug <- isJust <$> lookupEnv "COMFY_WORKFLOW_DEBUG"
  let emitLog loc source level message =
        when (debug || level >= LevelInfo) (defaultLogAction loc source level message)
  runSimpleEnvWith emitLog $ handle reportFailure do
    case args of
      (name : workflowPath : rest) -> run (convert name) workflowPath rest
      -- 名前とパスを別々に受け取る。
      -- パスはstoreの中にあり、
      -- ファイル名の頭にハッシュが付くのでそこからは名前を取れない。
      -- 使い方を誤った時のメッセージに出るのは名前の方である。
      _ -> throwM (ComfyFailure "引数はワークフローの名前とJSONのパスです")
 where
  reportFailure (ComfyFailure reason) = do
    logErrorN reason
    throwM (ExitFailure 1)
