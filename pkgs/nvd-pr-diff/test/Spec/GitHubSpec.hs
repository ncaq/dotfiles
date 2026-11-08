-- | 既存のコメントの探し方と、応答の読み方のテスト。
module Spec.GitHubSpec (tests) where

import Himari
import NvdPrDiff.GitHub
import Test.Sandwich

marker :: Text
marker = "<!-- nvd-pr-diff -->"

comment :: Integer -> Text -> Text -> Comment
comment commentId author body = Comment{commentId, author, body}

tests :: TopSpec
tests = do
  describe "findExisting" do
    it "botが書いた目印で始まる最初のコメントを選ぶ" do
      findExisting
        botLogin
        marker
        [ comment 1 botLogin "別の自動コメント"
        , comment 2 "ncaq" (marker <> "\n人が貼り付けたもの")
        , comment 3 botLogin (marker <> "\n## nvd diff")
        , comment 4 botLogin (marker <> "\n古い重複")
        ]
        `shouldBe` Just 3
    it "目印が途中にあるだけなら選ばない" do
      findExisting botLogin marker [comment 1 botLogin ("前置き\n" <> marker)] `shouldBe` Nothing
    it "無ければNothing" do
      findExisting botLogin marker [] `shouldBe` Nothing
  describe "Comment" do
    it "応答のJSONから必要な部分だけを読む" do
      eitherDecode
        ( "[{\"id\": 42, \"user\": {\"login\": \"github-actions[bot]\", \"id\": 1},"
            <> " \"body\": \"hi\", \"extra\": null}]"
        )
        `shouldBe` Right [comment 42 botLogin "hi"]
