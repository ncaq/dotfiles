-- | ブランチ名の検証のテスト。
module Spec.BranchNameSpec (tests) where

import GitRepoSubscribe.BranchName
import GitRepoSubscribe.Failure (BranchNameError (..))
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "parseBranchName" do
  for_ ["master", "feature/topic", "release-1.0", "日本語"] \name ->
    it (convert name <> "を受け付ける") do
      (branchNameText <$> parseBranchName name) `shouldBe` Right name
  for_
    [ ""
    , "@"
    , "-option"
    , "invalid..branch"
    , "branch."
    , "branch.lock"
    , ".hidden"
    , "nested/.hidden"
    , "/leading"
    , "trailing/"
    , "double//slash"
    , "with space"
    , "with~tilde"
    , "with^caret"
    , "with:colon"
    , "with?question"
    , "with*star"
    , "with[bracket"
    , "with\\backslash"
    , "with@{brace"
    , "with\ttab"
    ]
    \name ->
      it (show name <> "を拒否する") do
        parseBranchName name `shouldBe` Left (BranchNameError name)
