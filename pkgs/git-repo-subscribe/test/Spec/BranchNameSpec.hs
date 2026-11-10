-- | ブランチ名の検証のテスト。
module Spec.BranchNameSpec (tests) where

import Fixture (gitSucceedsOutside)
import GitRepoSubscribe.BranchName
import GitRepoSubscribe.Failure (BranchNameError (..))
import Himari
import Test.Sandwich

-- | 受け付けるべきブランチ名。
accepted :: [Text]
accepted =
  [ "master"
  , "feature/topic"
  , "release-1.0"
  , "日本語"
  , "a@b"
  , -- `@`だけの名前は参照名としては不正だが、ブランチ名としてはGitが受け付ける。
    "@"
  , -- `HEAD`が不正なのは名前の全体である時だけ。
    "heads/HEAD"
  , -- Gitが弾く制御文字はASCIIの範囲だけ。
    "c1\x80"
  ]

-- | 拒否すべきブランチ名。
rejected :: [Text]
rejected =
  [ ""
  , "HEAD"
  , "-option"
  , "invalid..branch"
  , "branch."
  , "branch.lock"
  , "a.lock/b"
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
  , "with\DELdelete"
  ]

tests :: TopSpec
tests = describe "parseBranchName" do
  for_ accepted \name ->
    it (show name <> "を受け付ける") do
      (branchNameText <$> parseBranchName name) `shouldBe` Right name
  for_ rejected \name ->
    it (show name <> "を拒否する") do
      parseBranchName name `shouldBe` Left (BranchNameError name)
  -- 規則を自前で書いているので、Git本体の判定とずれていないことを確かめる。
  -- 上の2つの一覧が思い込みで分けられていた場合もここで落ちる。
  describe "git check-ref-format --branchと判定が一致する" do
    for_ (accepted <> rejected) \name ->
      it (show name) do
        byGit <- gitSucceedsOutside ["check-ref-format", "--branch", convert name]
        isRight (parseBranchName name) `shouldBe` byGit
