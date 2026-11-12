-- | GitHubのAPIでの登録トークンの発行。
module GithubRunnerRegistrationToken.Api
  ( issueRegistrationToken
  , issuePolicy
  ) where

import GithubRunnerRegistrationToken.AccessToken (AccessToken (..))
import GithubRunnerRegistrationToken.Failure (ApiFailure (..))
import GithubRunnerRegistrationToken.RegistrationToken (RegistrationToken)
import GithubRunnerRegistrationToken.Repository (Repository (..))
import Himari
import Network.HTTP.Simple

-- | リポジトリのランナーの登録トークンを発行する。
--
-- 成功ではない状態コードと、読めない応答は`ApiFailure`として投げる。
-- 応答待ちの上限はhttp-clientの既定の30秒に任せる。
issueRegistrationToken
  :: (MonadIO m, MonadThrow m) => Text -> AccessToken -> Repository -> m RegistrationToken
issueRegistrationToken api (AccessToken token) (Repository repository) = do
  base <-
    parseRequest
      (convert (api <> "/repos/" <> repository <> "/actions/runners/registration-token"))
  response <- httpLBS (addressed base)
  let status = getResponseStatusCode response
      content = getResponseBody response
  unless (status `div` 100 == 2) (throwM (UnexpectedStatus status (convert content)))
  either (throwM . UndecodableBody . convert) pure (eitherDecode content)
 where
  addressed =
    setRequestMethod "POST"
      . setRequestBearerAuth (convert token)
      . setRequestHeader "Accept" ["application/vnd.github+json"]
      . setRequestHeader "X-GitHub-Api-Version" ["2022-11-28"]
      -- GitHubのAPIは`User-Agent`の無いリクエストを拒否する。
      . setRequestHeader "User-Agent" ["github-runner-registration-token"]

-- | 発行に失敗した時の試し直し方。
--
-- 起動直後はネットワークがまだ繋がっていないことがある。
-- 最初の発行に失敗するとコンテナも起動できないので、合わせて1分ほどは試し直す。
issuePolicy :: (MonadIO m) => RetryPolicyM m
issuePolicy = limitRetriesByCumulativeDelay 60000000 (capDelay 10000000 (fullJitterBackoff 1000000))
