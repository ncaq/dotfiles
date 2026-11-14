-- | 最新のコミットの情報を、flakeから読めるように一時的に注入する。
--
-- flakeはstagingされたファイルだけをソースに含めるので、
-- `last-commit.json`を書いて`git add -f`し、終わったら外して消す。
module DotfilesInstall.LastCommit.Stage
  ( lastCommitFile
  , readLastCommit
  , withStagedLastCommit
  ) where

import DotfilesInstall.Git (gitChecked, gitDiffers, gitRun, gitText)
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
hasChanges :: (MonadIO m, MonadThrow m) => FilePath -> m Bool
hasChanges repository =
  or <$> traverse (gitDiffers repository) [["diff", "--quiet"], ["diff", "--cached", "--quiet"]]

-- | 最新のコミットの情報を注入してから処理を走らせ、どう終わっても元に戻す。
--
-- 注入すると必ず変更がある状態になるので、情報は注入の前に集める。
withStagedLastCommit
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => FilePath -> m a -> m a
withStagedLastCommit repository action = do
  lastCommit <- readLastCommit repository
  -- ファイルを書くことと消すこと、stagingすることと外すことを、それぞれ対にする。
  -- 書いた後のstagingで失敗しても、外側の対がファイルを消す。
  bracket_ (write lastCommit) discard (bracket_ add reset action)
 where
  path = repository </> lastCommitFile
  write lastCommit = do
    logInfoN ("最新のコミットの情報を注入します: " <> convert lastCommitFile)
    writeBinaryFile path (convert (encode lastCommit))
  add = gitChecked repository ["add", "-f", "--", convert lastCommitFile]
  -- 戻せなくても害の無いファイルが残るだけなので、記録だけして続ける。
  reset = do
    code <- gitRun repository ["reset", "--quiet", "--", convert lastCommitFile]
    unless (code == ExitSuccess) $
      logWarnN ("注入したファイルをindexから外せませんでした: " <> convert (show code))
  discard = doesFileExist path >>= (`when` remove)
  -- `trash`があればそちらで消して、無い環境ではそのまま消す。
  remove =
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
