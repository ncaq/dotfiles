-- | fetchの前後でのworktreeの状態の比較のテスト。
module Spec.WorktreeSpec (tests) where

import GitRepoSubscribe.BranchName (parseBranchName)
import GitRepoSubscribe.CommitId (parseCommitId)
import GitRepoSubscribe.ConfiguredRemote (ConfiguredRemote (..))
import GitRepoSubscribe.Outcome (SkipReason (..))
import GitRepoSubscribe.Worktree
import Himari
import Test.Sandwich

-- | 1つの16進の数字を繰り返したコミットIDを持つ状態。
--
-- テスト用の値なので、検証に落ちたら例外にする。
worktreeState :: (MonadThrow m) => Text -> Char -> Text -> m WorktreeState
worktreeState origin digit branch =
  WorktreeState (Just (ConfiguredRemote origin))
    <$> either throwM pure (parseCommitId (convert (replicate 40 digit)))
    <*> (Just <$> either throwM pure (parseBranchName branch))

-- | ローカルの変更を調べたら失敗する検査。調べずに済ませたことを確かめるのに使う。
mustNotInspect :: Either Text Bool
mustNotInspect = Left "local changes must not be inspected"

tests :: TopSpec
tests = describe "detectConcurrentChange" do
  it "originが変わっていたらローカルの変更を調べずに報告する" do
    initial <- worktreeState "file:///initial" '0' "master"
    current <- worktreeState "file:///changed" '0' "master"
    detectConcurrentChange initial current mustNotInspect `shouldBe` Right (Just OriginChanged)
  it "HEADが変わっていたらローカルの変更を調べずに報告する" do
    initial <- worktreeState "file:///remote" '0' "master"
    current <- worktreeState "file:///remote" '1' "master"
    detectConcurrentChange initial current mustNotInspect `shouldBe` Right (Just HeadChanged)
  it "ブランチが変わっていたらローカルの変更を調べずに報告する" do
    initial <- worktreeState "file:///remote" '0' "master"
    current <- worktreeState "file:///remote" '0' "topic"
    detectConcurrentChange initial current mustNotInspect `shouldBe` Right (Just BranchChanged)
  it "他が同じでローカルの変更が増えていたら報告する" do
    unchanged <- worktreeState "file:///remote" '0' "master"
    detectConcurrentChange unchanged unchanged (Identity True)
      `shouldBe` Identity (Just LocalChangesDuringFetch)
  it "何も変わっていなければ通す" do
    unchanged <- worktreeState "file:///remote" '0' "master"
    detectConcurrentChange unchanged unchanged (Identity False) `shouldBe` Identity Nothing
