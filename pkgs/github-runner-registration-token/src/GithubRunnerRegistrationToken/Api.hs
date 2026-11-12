-- | GitHubのAPIでの登録トークンの発行。
module GithubRunnerRegistrationToken.Api
  ( issueRegistrationToken
  , recoveringIssue
  , issuePolicy
  ) where

import GithubRunnerRegistrationToken.AccessToken (AccessToken (..))
import GithubRunnerRegistrationToken.Failure (ApiFailure (..), ConfigFailure (..))
import GithubRunnerRegistrationToken.Microseconds (microseconds)
import GithubRunnerRegistrationToken.RegistrationToken (RegistrationToken)
import GithubRunnerRegistrationToken.Repository (Repository (..))
import Himari
import Network.HTTP.Simple
import Network.HTTP.Types (statusCode, statusIsSuccessful)

-- | リポジトリのランナーの登録トークンを発行する。
--
-- 接続の失敗やタイムアウト、成功ではない状態コード、読めない応答は`ApiFailure`として投げる。
-- APIのURLが読めない時は`InvalidApiUrl`を投げる。
-- http-conduitの例外は、送ろうとしたリクエストの全体を含む長い表示になるので、そのままは外へ出さない。
--
-- 応答待ちの上限はhttp-clientの既定の30秒に任せる。
issueRegistrationToken
  :: (MonadThrow m, MonadUnliftIO m) => Text -> AccessToken -> Repository -> m RegistrationToken
issueRegistrationToken api (AccessToken token) (Repository repository) = do
  base <-
    maybe
      (throwM (InvalidApiUrl api))
      pure
      ( parseRequest
          (convert (api <> "/repos/" <> repository <> "/actions/runners/registration-token"))
      )
  response <- handle transportFailure (httpLBS (addressed base))
  let status = getResponseStatus response
      content = getResponseBody response
  unless
    (statusIsSuccessful status)
    (throwM (UnexpectedStatus (statusCode status) (convert content)))
  either (throwM . UndecodableBody . convert) pure (eitherDecode content)
 where
  addressed =
    setRequestMethod "POST"
      . setRequestBearerAuth (convert token)
      . setRequestHeader "Accept" ["application/vnd.github+json"]
      . setRequestHeader "X-GitHub-Api-Version" ["2022-11-28"]
      -- GitHubのAPIは`User-Agent`の無いリクエストを拒否する。
      . setRequestHeader "User-Agent" ["github-runner-registration-token"]
  transportFailure = \case
    HttpExceptionRequest _ reason -> throwM (Unreachable (convert (show reason)))
    InvalidUrlException _ _ -> throwM (InvalidApiUrl api)

-- | 通信に由来し得る失敗だけを試し直しながら、発行を行う。
--
-- 試し直すのは、接続の失敗やタイムアウトと、成功ではない状態コードである。
-- 401や404も、ネットワークが壊れている時に途中の機器が返すことがあるので、状態コードでは分けない。
--
-- 読めない応答は、送り直しても結果が変わらないのですぐに終える。
-- `ApiFailure`ではない失敗も試し直さない。APIのURLの誤りがこれにあたる。
recoveringIssue :: (MonadUnliftIO m) => RetryPolicyM m -> m a -> m a
recoveringIssue policy action = recovering policy [const retryable] (const action)
 where
  retryable = Handler \case
    Unreachable _ -> pure True
    UnexpectedStatus _ _ -> pure True
    UndecodableBody _ -> pure False

-- | 発行に失敗した時の試し直し方。
--
-- 起動直後はネットワークがまだ繋がっていないことがある。
-- 最初の発行に失敗するとコンテナも起動できないので、合わせて1分ほどは試し直す。
-- 間隔は1秒から始めて、10秒まで広げていく。
issuePolicy :: (MonadIO m) => RetryPolicyM m
issuePolicy =
  limitRetriesByCumulativeDelay
    (microseconds 60)
    (capDelay (microseconds 10) (fullJitterBackoff (microseconds 1)))
