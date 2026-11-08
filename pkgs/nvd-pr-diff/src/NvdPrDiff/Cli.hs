-- | 全体の流れと、失敗の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
--
-- 評価するのはseminarだけにしている。
-- 他のホストはノイズが多いので当面は含めない。
-- home-managerはseminarのNixOSのトップレベルに含まれるので、別には出さない。
module NvdPrDiff.Cli
  ( host
  , run
  ) where

import Himari
import NvdPrDiff.Build (BuildFailure, Side (..), buildToplevel, nvdDiff, withBaseWorktree)
import NvdPrDiff.GitHub (GitHubFailure, Upsert, upsertComment)
import NvdPrDiff.Markdown (marker, render)
import NvdPrDiff.Report (ReportFailure, parseReport)
import NvdPrDiff.Target (Target (..), TargetFailure, readTarget)

-- | 比較するホスト。
host :: Text
host = "seminar"

-- | 投稿先を読み、両側を評価して比べ、PRコメントへ投稿する。
--
-- 想定している失敗は理由をログに出して`ExitFailure 1`にする。
-- nvdの出力を読めなかった時は、megaparsecの複数行の説明がそのまま理由に付く。
-- それ以外の例外はこちらの不具合なので変換せずに通す。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => m Upsert
run =
  handle (report @TargetFailure)
    . handle (report @BuildFailure)
    . handle (report @ReportFailure)
    . handle (report @GitHubFailure)
    $ do
      target <- readTarget
      withSystemTempDirectory "nvd-pr-diff" \dir -> do
        (before, after) <- withBaseWorktree (dir </> "base") target.baseRef \baseTree ->
          concurrently (buildToplevel Base baseTree attr) (buildToplevel Head "." attr)
        output <- nvdDiff before after
        parsed <- either throwM pure (parseReport output)
        upsertComment target marker (render host target.baseRef parsed)
 where
  attr = ".#nixosConfigurations.\"" <> host <> "\".config.system.build.toplevel"
  report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
  report failure = do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)
