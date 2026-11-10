-- | 更新しなかった理由の警告文のテスト。
module Spec.OutcomeSpec (tests) where

import GitRepoSubscribe.BranchName (parseBranchName)
import GitRepoSubscribe.ConfiguredRemote (ConfiguredRemote (..))
import GitRepoSubscribe.Outcome
import GitRepoSubscribe.PartialCloneFilter (parsePartialCloneFilter)
import GitRepoSubscribe.RemoteUrl (parseRemoteUrl)
import GitRepoSubscribe.Repository (Repository (..))
import GitRepoSubscribe.WorktreePath (parseWorktreePath)
import Himari
import Test.Sandwich

-- | 警告文に出る値を確かめるための購読。
--
-- テスト用の値なので、検証に落ちたら例外にする。
sample :: (MonadThrow m) => m Repository
sample =
  either throwM pure $
    Repository
      <$> over _Left toException (parseRemoteUrl "https://example.com/repo.git")
      <*> over _Left toException (parseWorktreePath "/home/user/repo")
      <*> over _Left toException (parsePartialCloneFilter "blob:none")

tests :: TopSpec
tests = describe "skipWarning" do
  it "置き場所の状態が理由なら置き場所を示す" do
    repository <- sample
    skipWarning repository LocalChanges
      `shouldBe` "/home/user/repo has local changes; skipping update."
  it "リモートが理由ならURLを示す" do
    repository <- sample
    skipWarning repository RemoteUnavailable
      `shouldBe` ( "unable to query the default branch of https://example.com/repo.git"
                     <> "; skipping update."
                 )
  it "originが違う時は実際のURLと設定のURLを示す" do
    repository <- sample
    skipWarning repository (OriginMismatch (ConfiguredRemote "git@example.com:fork.git"))
      `shouldBe` ( "origin URL of /home/user/repo is git@example.com:fork.git"
                     <> ", expected https://example.com/repo.git; skipping update."
                 )
  it "デフォルトブランチ以外にいる時は両方のブランチを示す" do
    repository <- sample
    topic <- either throwM pure (parseBranchName "topic")
    master <- either throwM pure (parseBranchName "master")
    skipWarning repository (NotDefaultBranch topic master)
      `shouldBe` "/home/user/repo is on topic, not the default branch master; skipping update."
