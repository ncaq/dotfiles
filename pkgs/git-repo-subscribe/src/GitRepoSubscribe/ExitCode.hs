-- | 失敗したGitの終了コードから、このコマンドの終了コードを決める。
module GitRepoSubscribe.ExitCode
  ( gitExitCode
  ) where

import Himari

-- | 失敗したGitの終了コードを、このコマンドの終了コードにする。
--
-- 1から255の終了コードはそのまま返す。
-- それ以外は終了コードとして表せないか失敗を表さないので、1にする。
-- シグナルで止まった時の負の値や、失敗の報告なのに成功を表す0がこれに当たる。
gitExitCode :: ExitCode -> ExitCode
gitExitCode = \case
  ExitFailure code | 0 < code && code < 256 -> ExitFailure code
  _ -> ExitFailure 1
