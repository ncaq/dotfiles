-- | 最新のコミットの情報のJSONの形のテスト。
module Spec.LastCommitSpec (tests) where

import DotfilesInstall.LastCommit
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "LastCommit" do
  it "nixos/core/label.nixが読む名前と型でJSONにする" do
    toJSON (LastCommit "feat(boot): message" True "feature/branch")
      `shouldBe` [aesonQQ|{
                   "subject": "feat(boot): message",
                   "dirty": true,
                   "branch": "feature/branch"
                 }|]
