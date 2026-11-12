-- | 登録トークンの発行のHTTPでの送信のテスト。
--
-- 偽のサーバを空いているポートに立てて、実際にHTTPで送る。
module Spec.ApiSpec (tests) where

import GithubRunnerRegistrationToken.Api (issueRegistrationToken)
import GithubRunnerRegistrationToken.Failure (ApiFailure (..))
import GithubRunnerRegistrationToken.RegistrationToken (RegistrationToken (..))
import GithubRunnerRegistrationToken.Repository (Repository)
import Himari
import Network.HTTP.Types (hAccept, hAuthorization, hUserAgent, status201, status401)
import Network.Wai (Application, rawPathInfo, requestHeaders, requestMethod, responseLBS)
import Network.Wai.Handler.Warp (testWithApplication)
import Test.Sandwich

-- | 偽のGitHubのAPIが返す、発行の応答。
newtype Issued = Issued
  { token :: Text
  }
  deriving stock (Generic)
  deriving (ToJSON) via CustomJSON '[] Issued

-- | リポジトリごとに決まった応答を返す、偽のGitHubのAPI。
--
-- `ncaq/echo`は、受け取ったリクエストのメソッドとヘッダを`|`で繋いだものをトークンとして返す。
application :: Application
application request respond =
  respond case rawPathInfo request of
    "/repos/ncaq/dotfiles/actions/runners/registration-token" ->
      responseLBS status201 [] (encode Issued{token = "AABBCC"})
    "/repos/ncaq/echo/actions/runners/registration-token" ->
      responseLBS status201 [] (encode Issued{token = echo})
    "/repos/ncaq/forbidden/actions/runners/registration-token" ->
      responseLBS status401 [] "Bad credentials"
    "/repos/ncaq/garbled/actions/runners/registration-token" ->
      responseLBS status201 [] "<html>"
    _ -> responseLBS status201 [] "{}"
 where
  echo =
    convert (requestMethod request)
      <> foldMap
        (\name -> "|" <> maybe "" convert (lookup name (requestHeaders request)))
        [hAuthorization, hAccept, hUserAgent, "X-GitHub-Api-Version"]

-- | 偽のGitHubのAPIに対して発行する。
issueFrom :: (MonadThrow m, MonadUnliftIO m) => Repository -> m RegistrationToken
issueFrom repository = withRunInIO \runInIO ->
  testWithApplication (pure application) \port ->
    runInIO
      ( issueRegistrationToken
          ("http://127.0.0.1:" <> convert (show port))
          "access-token"
          repository
      )

tests :: TopSpec
tests = describe "issueRegistrationToken" do
  it "リポジトリの発行のパスへ送って、応答のトークンを返す" do
    issueFrom "ncaq/dotfiles" >>= (`shouldBe` "AABBCC")
  it "POSTで、Bearerのトークンと決まったヘッダを付けて送る" do
    issueFrom "ncaq/echo"
      >>= ( `shouldBe`
              RegistrationToken
                ( "POST"
                    <> "|Bearer access-token"
                    <> "|application/vnd.github+json"
                    <> "|github-runner-registration-token"
                    <> "|2022-11-28"
                )
          )
  it "成功ではない状態コードは、状態コードと本文を持つ失敗にする" do
    issueFrom "ncaq/forbidden" `shouldThrow` (== UnexpectedStatus 401 "Bad credentials")
  it "JSONとして読めない本文は失敗にする" do
    issueFrom "ncaq/garbled" `shouldThrow` \case
      UndecodableBody _ -> True
      _ -> False
  it "tokenの無い応答は失敗にする" do
    issueFrom "ncaq/missing" `shouldThrow` \case
      UndecodableBody _ -> True
      _ -> False
