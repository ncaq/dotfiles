-- | 既存のコメントの探し方と、応答の読み方のテスト。
module Spec.GitHubSpec (tests) where

import Himari
import NvdPrDiff.GitHub
import Test.Sandwich

marker :: Text
marker = "<!-- nvd-pr-diff -->"

comment :: Integer -> Text -> Text -> Comment
comment commentId author body = Comment{commentId, author, body}

-- | 全部で`total`件あるコメントを100件ずつ返す取り方で集めて、
-- 集まった一覧と取りに行ったページ番号の並びを返す。
pagesOf :: Int -> ([Int], [Int])
pagesOf total =
  runState
    ( collectPages \n -> do
        modify (<> [n])
        pure (take perPage (drop ((n - 1) * perPage) [1 .. total]))
    )
    []

tests :: TopSpec
tests = do
  describe "collectPages" do
    it "0件なら1ページ取って終わる" do
      pagesOf 0 `shouldBe` ([], [1])
    it "1ページに満たなければ1ページで終わる" do
      pagesOf 99 `shouldBe` ([1 .. 99], [1])
    it "ちょうど1ページ分なら次の空のページまで取る" do
      pagesOf 100 `shouldBe` ([1 .. 100], [1, 2])
    it "1ページを超えれば2ページ目も繋げる" do
      pagesOf 101 `shouldBe` ([1 .. 101], [1, 2])
  describe "acceptStatus" do
    for_ [200, 201, 204] \status ->
      it (show status <> "は本文を返す") do
        acceptStatus status "ok" `shouldBe` Right "ok"
    for_ [301, 404, 500] \status ->
      it (show status <> "は状態コードと本文を添えて失敗にする") do
        acceptStatus status "{\"message\":\"nope\"}"
          `shouldBe` Left (RequestFailed status "{\"message\":\"nope\"}")
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
