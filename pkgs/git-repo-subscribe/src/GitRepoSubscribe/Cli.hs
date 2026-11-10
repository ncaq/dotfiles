-- | コマンドライン引数の解釈と、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
--
-- lensの`argument`はoptparse-applicativeの位置引数と名前がぶつかるので、Himariの側を隠す。
module GitRepoSubscribe.Cli
  ( run
  ) where

import GitRepoSubscribe.ExitCode (gitExitCode)
import GitRepoSubscribe.Failure (BranchNameError, CommitIdError, GitFailure (..))
import GitRepoSubscribe.Outcome (Outcome (..), skipWarning)
import GitRepoSubscribe.PartialCloneFilter (parsePartialCloneFilter)
import GitRepoSubscribe.RemoteUrl (parseRemoteUrl)
import GitRepoSubscribe.Repository (Repository (..))
import GitRepoSubscribe.Subscribe (subscribe)
import GitRepoSubscribe.WorktreePath (parseWorktreePath)
import Himari hiding (argument)
import Options.Applicative

-- | コマンドライン引数を受けて、リポジトリを1つ購読する。
--
-- 安全に更新できなかった時は警告を出して成功で終わる。
-- 一時的な通信の不調などで呼び出し側の処理全体を止めないためである。
--
-- Gitのコマンドが失敗した時は、説明はGit自身が既に出しているので、
-- 1から255の終了コードはそのまま返し、それ以外は1にする。
-- それ以外の想定している失敗は理由をログに出して`ExitFailure 1`にする。
-- 引数が誤っている時は、使い方を標準エラー出力へ出して`ExitFailure 1`にする。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run argv = do
  repository <-
    liftIO . handleParseResult $
      execParserPure defaultPrefs parserInfo argv
  outcome <-
    handle reportGit
      . handle (report @BranchNameError)
      . handle (report @CommitIdError)
      $ subscribe repository
  case outcome of
    Cloned -> pure ()
    Updated -> pure ()
    Skipped reason -> logWarnN (skipWarning repository reason)
 where
  reportGit :: (MonadLogger m, MonadThrow m) => GitFailure -> m a
  reportGit = \case
    GitFailed _ code -> throwM (gitExitCode code)
    failure -> report failure
  report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
  report failure = do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)

parserInfo :: ParserInfo Repository
parserInfo =
  info
    (repositoryParser <**> helper)
    (progDesc "Clone and safely update a Git repository")

repositoryParser :: Parser Repository
repositoryParser =
  Repository
    <$> positional (parseRemoteUrl . convert) "URL" "Git remote URL to subscribe to"
    <*> positional parseWorktreePath "PATH" "Absolute worktree destination path"
    <*> positional
      (parsePartialCloneFilter . convert)
      "FILTER"
      "Partial clone filter for the initial clone, such as blob:none"

-- | 検証を通った値だけを受け付ける位置引数。
positional
  :: (Exception e) => (String -> Either e a) -> String -> String -> Parser a
positional parse name description =
  argument
    (eitherReader (over _Left displayException . parse))
    (metavar name <> help description)
