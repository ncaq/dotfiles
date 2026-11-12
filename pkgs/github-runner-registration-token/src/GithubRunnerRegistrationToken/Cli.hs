-- | 環境変数からの設定の読み取りと、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
module GithubRunnerRegistrationToken.Cli
  ( run
  , report
  ) where

import GithubRunnerRegistrationToken.AccessToken (readAccessToken)
import GithubRunnerRegistrationToken.Api (issuePolicy, issueRegistrationToken)
import GithubRunnerRegistrationToken.Config (Config (..), configFrom)
import GithubRunnerRegistrationToken.Failure (ApiFailure, ConfigFailure)
import GithubRunnerRegistrationToken.TokenFile (tokenFileName, writeTokenFile)
import Himari

-- | プロセスの環境変数を設定として、登録トークンを発行してファイルに置く。引数は取らない。
--
-- アクセストークンはこのプロセスだけが持ち、
-- ランナーにはランナーの登録にしか使えない登録トークンだけを渡す。
--
-- 設定が揃わない時と、GitHubのAPIの応答を使えなかった時は、理由をログに出して`ExitFailure 1`にする。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run _ = handle (report @ConfigFailure) . handle (report @ApiFailure) $ do
  environment <- getEnvironment
  config <- configFrom (\name -> convert <$> lookup (convert name) environment)
  accessToken <- readAccessToken config.accessTokenFile
  registrationToken <-
    recoverAll
      issuePolicy
      (const (issueRegistrationToken config.api accessToken config.repository))
  writeTokenFile (config.runtimeDirectory </> tokenFileName) registrationToken
  logInfoN ("登録トークンを発行しました: " <> convert (show config.repository))

-- | 想定している失敗を、ログに出して`ExitFailure 1`にする。
report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
report failure = do
  logErrorN (convert (displayException failure))
  throwM (ExitFailure 1)
