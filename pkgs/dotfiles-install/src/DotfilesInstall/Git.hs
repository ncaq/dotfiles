-- | Gitの子プロセスの起動。
--
-- どれも対象のリポジトリを最初の引数に取る。
module DotfilesInstall.Git
  ( gitRun
  , gitChecked
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

-- | Gitを実行して、標準出力を末尾の改行を除いた文字列として返す。失敗したら例外にする。
gitText :: (MonadIO m, MonadThrow m) => FilePath -> [Text] -> m Text
gitText repository args = do
  (code, out) <- readProcessStdout (gitProcess repository args)
  unless (code == ExitSuccess) (throwM (GitFailed args code))
  pure (dropWhileEnd (== '\n') (convert out))
