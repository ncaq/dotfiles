-- | baseとPRの評価と、nvdでの比較。
--
-- base側は`git worktree`で別のディレクトリへ展開して、そこで`nix build`する。
-- 2つの`nix build`は並べて走らせる。
-- 評価の間は一時的にメモリを多く使うが、
-- Nixデーモンがロックを持っているのでビルドが競合することはない。
-- 進捗は標準エラー出力をそのまま継いでCIのログへ流す。
module NvdPrDiff.Build
  ( Side (..)
  , BuildFailure (..)
  , withBaseWorktree
  , buildToplevel
  , nvdDiff
  ) where

import Data.Text (strip)
import Himari

-- | 比較のどちら側か。
data Side
  = Base
  | Head
  deriving stock (Eq, Show)

-- | 評価や比較が通らなかった理由。
data BuildFailure
  = -- | base側のworktreeを作れなかった。
    WorktreeFailed ExitCode
  | -- | `nix build`が失敗した。どちら側か。
    BuildFailed Side ExitCode
  | -- | `nvd diff`が失敗した。
    DiffFailed ExitCode
  deriving stock (Eq, Show)

instance Exception BuildFailure where
  displayException = \case
    WorktreeFailed code -> "base側のworktreeを作れませんでした: " <> show code
    BuildFailed side code -> describe side <> "の評価が失敗しました: " <> show code
    DiffFailed code -> "nvd diffが失敗しました: " <> show code

describe :: Side -> String
describe = \case
  Base -> "base"
  Head -> "PR"

-- | ベースブランチをworktreeへ展開して渡し、終わったら外す。
--
-- `origin`からの取得はprivateなリポジトリで失敗することがあるが、
-- GitHub Actionsのcheckoutが既に取っていれば足りるので、記録だけして続ける。
withBaseWorktree
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => FilePath -> Text -> (FilePath -> m a) -> m a
withBaseWorktree dir baseRef action = do
  fetched <- runProcess (proc "git" ["fetch", "--no-tags", "origin", "--", convert baseRef])
  unless (fetched == ExitSuccess) $
    logWarnN ("origin/" <> baseRef <> "を取得できなかったので手元の参照を使います: " <> convert (show fetched))
  bracket_ add remove (action dir)
 where
  remoteRef = "origin/" <> convert baseRef
  add = do
    code <- runProcess (proc "git" ["worktree", "add", "--detach", dir, "--", remoteRef])
    unless (code == ExitSuccess) (throwM (WorktreeFailed code))
  -- ディレクトリ自体は一時ディレクトリごと消えるので、ここではgitの記録を外す。
  -- 外せなくても結果には関わらないので、記録だけして続ける。
  remove = do
    code <- runProcess (proc "git" ["worktree", "remove", "--force", dir])
    unless (code == ExitSuccess) $
      logWarnN ("worktreeを外せませんでした: " <> convert (show code))

-- | 指定のディレクトリのflakeを評価して、成果物のstore pathを返す。
buildToplevel :: (MonadIO m, MonadLogger m, MonadThrow m) => Side -> FilePath -> Text -> m Text
buildToplevel side dir attr = do
  logInfoN (convert (describe side) <> "を評価します: " <> attr)
  (code, out) <-
    readProcessStdout
      (setWorkingDir dir (proc "nix" ["build", "--no-link", "--print-out-paths", convert attr]))
  unless (code == ExitSuccess) (throwM (BuildFailed side code))
  pure (strip (convert out))

-- | 2つのstore pathを`nvd diff`で比べて、その標準出力を返す。
nvdDiff :: (MonadIO m, MonadLogger m, MonadThrow m) => Text -> Text -> m Text
nvdDiff before after = do
  logInfoN "nvdで比較します"
  (code, out) <-
    readProcessStdout (proc "nvd" ["--color", "never", "diff", convert before, convert after])
  unless (code == ExitSuccess) (throwM (DiffFailed code))
  pure (convert out)
