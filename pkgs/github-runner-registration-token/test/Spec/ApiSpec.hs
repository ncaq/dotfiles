-- | 登録トークンの発行のHTTPでの送信のテスト。
--
-- 偽のサーバを空いているポートに立てて、実際にHTTPで送る。
module Spec.ApiSpec (tests) where

import Fixture
import GithubRunnerRegistrationToken.Api (issueRegistrationToken)
import GithubRunnerRegistrationToken.Failure (ApiFailure (..))
import GithubRunnerRegistrationToken.RegistrationToken (RegistrationToken (..))
import GithubRunnerRegistrationToken.Repository (Repository)
import Himari
import Test.Sandwich

-- | 偽のGitHubのAPIに対して発行する。
issueFrom :: (MonadThrow m, MonadUnliftIO m) => Repository -> m RegistrationToken
issueFrom repository = withApi \api -> issueRegistrationToken api "access-token" repository

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
