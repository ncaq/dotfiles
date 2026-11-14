-- | 最新のコミットの情報を、flakeから読めるように一時的に注入する。
--
-- flakeはstagingされたファイルだけをソースに含めるので、
-- `last-commit.json`を書いて`git add -f`し、終わったら外して消す。
module DotfilesInstall.LastCommit.Stage
  ( lastCommitFile
  , readLastCommit
  , withStagedLastCommit
  ) where

import DotfilesInstall.Git (gitChecked, gitRun, gitText)
import DotfilesInstall.LastCommit (LastCommit (..))
import Himari

-- | 注入するファイルの、リポジトリルートからの相対パス。
lastCommitFile :: FilePath
lastCommitFile = "last-commit.json"

-- | リポジトリから最新のコミットの情報を集める。
readLastCommit :: (MonadIO m, MonadThrow m) => FilePath -> m LastCommit
readLastCommit repository =
  LastCommit
    <$> gitText repository ["log", "-1", "--format=%s"]
    <*> hasChanges repository
    <*> gitText repository ["rev-parse", "--abbrev-ref", "HEAD"]

-- | 追跡しているファイルに、コミットしていない変更があるか。
hasChanges :: (MonadIO m) => FilePath -> m Bool
hasChanges repository =
  any (/= ExitSuccess)
    <$> traverse (gitRun repository) [["diff", "--quiet"], ["diff", "--cached", "--quiet"]]

-- | 最新のコミットの情報を注入してから処理を走らせ、どう終わっても元に戻す。
--
-- 注入すると必ず変更がある状態になるので、情報は注入の前に集める。
withStagedLastCommit
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => FilePath -> m a -> m a
withStagedLastCommit repository action = do
  lastCommit <- readLastCommit repository
  (stage lastCommit *> action) `finally` unstage
 where
  path = repository </> lastCommitFile
  stage lastCommit = do
    logInfoN ("最新のコミットの情報を注入します: " <> convert lastCommitFile)
    writeBinaryFile path (convert (encode lastCommit))
    gitChecked repository ["add", "-f", "--", lastCommitFile]
  -- 戻せなくても害の無いファイルが残るだけなので、記録だけして続ける。
  unstage = do
    reset <- gitRun repository ["reset", "--quiet", "--", lastCommitFile]
    unless (reset == ExitSuccess) $
      logWarnN ("注入したファイルをindexから外せませんでした: " <> convert (show reset))
    exists <- doesFileExist path
    when exists discard
  -- `trash`があればそちらで消して、無い環境ではそのまま消す。
  discard =
    findExecutable "trash" >>= \case
      Just trash -> do
        code <- runProcess (proc trash [path])
        unless (code == ExitSuccess) $
          logWarnN ("注入したファイルをtrashで消せませんでした: " <> convert (show code))
      Nothing ->
        tryIO (removeFile path) >>= \case
          Right () -> pure ()
          Left failure ->
            logWarnN ("注入したファイルを消せませんでした: " <> convert (displayException failure))
