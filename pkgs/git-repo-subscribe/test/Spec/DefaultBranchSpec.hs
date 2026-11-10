-- | リモートのデフォルトブランチの読み取りのテスト。
module Spec.DefaultBranchSpec (tests) where

import GitRepoSubscribe.BranchName (branchNameText)
import GitRepoSubscribe.DefaultBranch
import GitRepoSubscribe.Failure (BranchNameError (..))
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "parseDefaultBranch" do
  it "HEADが指すブランチを読む" do
    (fmap branchNameText <$> parseDefaultBranch "ref: refs/heads/master\tHEAD\nabc\tHEAD\n")
      `shouldBe` Right (Just "master")
  it "HEAD以外のsymrefは無視する" do
    parseDefaultBranch "ref: refs/heads/topic\trefs/heads/topic\n" `shouldBe` Right Nothing
  it "不正なブランチ名を報告する" do
    parseDefaultBranch "ref: refs/heads/invalid..branch\tHEAD\n"
      `shouldBe` Left (BranchNameError "invalid..branch")
