-- | アクセストークンの読み方のテスト。
module Spec.AccessTokenSpec (tests) where

import GithubRunnerRegistrationToken.AccessToken (AccessToken, readAccessToken)
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "AccessToken" do
  it "ファイルの末尾の改行を落として読む" do
    withSystemTempDirectory "github-runner-registration-token-test" \directory -> do
      let path = directory </> "pat"
      liftIO (writeFile path "github_pat_example\n")
      readAccessToken path >>= (`shouldBe` "github_pat_example")
  it "表示しても中身を出さない" do
    show ("github_pat_example" :: AccessToken) `shouldBe` "AccessToken <redacted>"
