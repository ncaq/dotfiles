-- | worktreeのパスの検証のテスト。
module Spec.WorktreePathSpec (tests) where

import GitRepoSubscribe.Failure (WorktreePathError (..))
import GitRepoSubscribe.WorktreePath
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "parseWorktreePath" do
  it "絶対パスを受け付ける" do
    (worktreeFilePath <$> parseWorktreePath "/tmp/repository") `shouldBe` Right "/tmp/repository"
  it "相対パスを拒否する" do
    parseWorktreePath "relative/repository" `shouldBe` Left RelativePath
  it "`..`を含むパスを拒否する" do
    parseWorktreePath "/tmp/../repository" `shouldBe` Left NotNormalizedPath
  it "ルートを拒否する" do
    parseWorktreePath "/" `shouldBe` Left RootPath
