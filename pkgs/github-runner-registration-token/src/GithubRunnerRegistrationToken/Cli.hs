-- | 環境変数からの設定の読み取りと、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
module GithubRunnerRegistrationToken.Cli
  ( run
  , runWith
  , report
  ) where

import GithubRunnerRegistrationToken.AccessToken (readAccessToken)
import GithubRunnerRegistrationToken.Api (issuePolicy, issueRegistrationToken, recoveringIssue)
import GithubRunnerRegistrationToken.Config (Config (..), configFrom)
import GithubRunnerRegistrationToken.Failure (ApiFailure, ConfigFailure)
import GithubRunnerRegistrationToken.Repository (Repository (..))
import GithubRunnerRegistrationToken.TokenFile (tokenFileName, writeTokenFile)
import Himari

-- | プロセスの環境変数を設定として、登録トークンを発行してファイルに置く。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => m ()
run = do
  environment <- getEnvironment
  runWith issuePolicy (\name -> convert <$> lookup (convert name) environment)

-- | 発行の試し直し方と環境変数を引く関数を受け取って、登録トークンを発行してファイルに置く。
--
-- アクセストークンはこのプロセスだけが持ち、
-- ランナーにはランナーの登録にしか使えない登録トークンだけを渡す。
--
-- 設定が誤っている時と、GitHubのAPIから登録トークンを得られなかった時は、
-- 理由をログに出して`ExitFailure 1`にする。接続できなかった時もこれに含む。
runWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m)
  => RetryPolicyM m
  -> (Text -> Maybe Text)
  -> m ()
runWith policy lookupVariable = handle (report @ConfigFailure) . handle (report @ApiFailure) $ do
  config <- configFrom lookupVariable
  accessToken <- readAccessToken config.accessTokenFile
  registrationToken <-
    recoveringIssue policy (issueRegistrationToken config.api accessToken config.repository)
  writeTokenFile (config.runtimeDirectory </> tokenFileName) registrationToken
  let Repository repository = config.repository
  logInfoN ("登録トークンを発行しました: " <> repository)

-- | 想定している失敗を、ログに出して`ExitFailure 1`にする。
report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
report failure = do
  logErrorN (convert (displayException failure))
  throwM (ExitFailure 1)
