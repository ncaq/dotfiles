-- | 登録トークンの発行のHTTPでの送信と、試し直しの対象のテスト。
--
-- 偽のサーバを空いているポートに立てて、実際にHTTPで送る。
module Spec.ApiSpec (tests) where

import Fixture
import GithubRunnerRegistrationToken.Api (issueRegistrationToken, recoveringIssue)
import GithubRunnerRegistrationToken.Failure (ApiFailure (..), ConfigFailure (..))
import GithubRunnerRegistrationToken.RegistrationToken (RegistrationToken (..))
import GithubRunnerRegistrationToken.Repository (Repository)
import Himari
import Test.Sandwich

-- | 偽のGitHubのAPIに対して発行する。
issueFrom :: (MonadThrow m, MonadUnliftIO m) => Repository -> m RegistrationToken
issueFrom repository = withApi \api -> issueRegistrationToken api "access-token" repository

-- | 決まった失敗を投げ続けるアクションを、2回まで試し直す設定で実行して、呼ばれた回数を返す。
attemptsOf :: (Exception e, MonadThrow m, MonadUnliftIO m) => e -> m Int
attemptsOf failure = do
  attempts <- newIORef (0 :: Int)
  void
    ( tryAny
        ( recoveringIssue
            (limitRetries 2)
            (modifyIORef' attempts (+ 1) >> throwM failure)
        )
    )
  readIORef attempts

tests :: TopSpec
tests = do
  describe "issueRegistrationToken" do
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
    it "接続できなければ、接続の失敗にする" do
      api <- closedApi
      issueRegistrationToken api "access-token" "ncaq/dotfiles" `shouldThrow` \case
        Unreachable _ -> True
        _ -> False
    it "APIのURLが読めなければ、設定の失敗にする" do
      issueRegistrationToken "not a url" "access-token" "ncaq/dotfiles"
        `shouldThrow` (== InvalidApiUrl "not a url")
  describe "recoveringIssue" do
    it "接続の失敗は試し直す" do
      attemptsOf (Unreachable "ConnectionFailure") >>= (`shouldBe` 3)
    it "成功ではない状態コードは試し直す" do
      attemptsOf (UnexpectedStatus 401 "Bad credentials") >>= (`shouldBe` 3)
    it "読めない応答は試し直さない" do
      attemptsOf (UndecodableBody "Unexpected end-of-input") >>= (`shouldBe` 1)
    it "APIのURLの誤りは試し直さない" do
      attemptsOf (InvalidApiUrl "not a url") >>= (`shouldBe` 1)
