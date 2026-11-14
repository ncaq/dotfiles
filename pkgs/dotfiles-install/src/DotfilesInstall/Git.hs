-- | Gitの子プロセスの起動。
--
-- どれも対象のリポジトリを最初の引数に取る。
module DotfilesInstall.Git
  ( gitRun
  , gitChecked
  , gitDiffers
  , gitText
  ) where

import Data.Text (dropWhileEnd)
import DotfilesInstall.Failure (GitFailure (..))
import Himari

gitProcess :: FilePath -> [Text] -> ProcessConfig () () ()
gitProcess repository args = proc "git" (["-C", repository] <> (convert <$> args))

-- | Gitを実行して終了コードを返す。出力はそのまま流す。
gitRun :: (MonadIO m) => FilePath -> [Text] -> m ExitCode
gitRun repository = runProcess . gitProcess repository

-- | Gitを実行して、失敗したら例外にする。出力はそのまま流す。
gitChecked :: (MonadIO m, MonadThrow m) => FilePath -> [Text] -> m ()
gitChecked repository args = do
  code <- gitRun repository args
  unless (code == ExitSuccess) (throwM (GitFailed args code))

-- | `git diff --quiet`のように、差分の有無を終了コードで答えるコマンドを実行する。
--
-- 差分が無い時の0と、ある時の1だけを答えとして受け取り、それ以外は失敗として例外にする。
gitDiffers :: (MonadIO m, MonadThrow m) => FilePath -> [Text] -> m Bool
gitDiffers repository args =
  gitRun repository args >>= \case
    ExitSuccess -> pure False
    ExitFailure 1 -> pure True
    code -> throwM (GitFailed args code)

-- | Gitを実行して、標準出力を末尾の改行を除いた文字列として返す。失敗したら例外にする。
gitText :: (MonadIO m, MonadThrow m) => FilePath -> [Text] -> m Text
gitText repository args = do
  (code, out) <- readProcessStdout (gitProcess repository args)
  unless (code == ExitSuccess) (throwM (GitFailed args code))
  pure (dropWhileEnd (== '\n') (convert out))
