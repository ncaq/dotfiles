-- | 設定の環境変数の読み方のテスト。
module Spec.ConfigSpec (tests) where

import GithubRunnerRegistrationToken.Config (Config (..), configFrom)
import GithubRunnerRegistrationToken.Failure (ConfigFailure (..))
import Himari
import Test.Sandwich

-- | 揃っている設定。
complete :: [(Text, Text)]
complete =
  [ ("GITHUB_RUNNER_REGISTRATION_TOKEN_REPOSITORY", "ncaq/dotfiles")
  , ("GITHUB_RUNNER_REGISTRATION_TOKEN_API", "https://api.github.com")
  , ("GITHUB_RUNNER_REGISTRATION_TOKEN_ACCESS_TOKEN_FILE", "/run/secrets/runner-registration-token")
  , ("RUNTIME_DIRECTORY", "/run/github-runner-dotfiles-x64-registration-token")
  ]

tests :: TopSpec
tests = describe "configFrom" do
  it "揃っていれば読む" do
    configFrom (`lookup` complete)
      >>= ( `shouldBe`
              Config
                { repository = "ncaq/dotfiles"
                , api = "https://api.github.com"
                , accessTokenFile = "/run/secrets/runner-registration-token"
                , runtimeDirectory = "/run/github-runner-dotfiles-x64-registration-token"
                }
          )
  for_ (fst <$> complete) \variable -> do
    it (convert variable <> "が無ければ失敗にする") do
      configFrom (`lookup` filter ((/= variable) . fst) complete)
        `shouldThrow` (== MissingVariable variable)
    it (convert variable <> "が空でも失敗にする") do
      configFrom (`lookup` ((variable, "") : complete))
        `shouldThrow` (== MissingVariable variable)
