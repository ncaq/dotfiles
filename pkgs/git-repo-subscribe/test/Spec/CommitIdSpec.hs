-- | コミットのIDの検証のテスト。
module Spec.CommitIdSpec (tests) where

import GitRepoSubscribe.CommitId
import GitRepoSubscribe.Failure (CommitIdError (..))
import Himari
import Test.Sandwich

-- | 1つの文字を繰り返した値。
filledWith :: Int -> Char -> Text
filledWith count = convert . replicate count

tests :: TopSpec
tests = describe "parseCommitId" do
  it "SHA-1の長さを受け付ける" do
    void (parseCommitId (filledWith 40 'a')) `shouldBe` Right ()
  it "SHA-256の長さを受け付ける" do
    void (parseCommitId (filledWith 64 '0')) `shouldBe` Right ()
  it "大文字と小文字の違いを同じIDと見なす" do
    parseCommitId (filledWith 40 'A') `shouldBe` parseCommitId (filledWith 40 'a')
  for_ [("省略されたID", "abc1234"), ("16進でない文字", filledWith 40 'g')] \(name, value) ->
    it (name <> "を拒否する") do
      parseCommitId value `shouldBe` Left (CommitIdError value)
