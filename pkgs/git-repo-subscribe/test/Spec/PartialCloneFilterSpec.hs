-- | partial cloneのフィルタの検証のテスト。
module Spec.PartialCloneFilterSpec (tests) where

import GitRepoSubscribe.Failure (PartialCloneFilterError (..))
import GitRepoSubscribe.PartialCloneFilter
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "parsePartialCloneFilter" do
  it "フィルタを`--filter=`の引数にする" do
    (filterArgument <$> parsePartialCloneFilter "blob:limit=1m")
      `shouldBe` Right "--filter=blob:limit=1m"
  it "組み合わせたフィルタを受け付ける" do
    (filterArgument <$> parsePartialCloneFilter "combine:blob:none+tree:0")
      `shouldBe` Right "--filter=combine:blob:none+tree:0"
  it "空を拒否する" do
    parsePartialCloneFilter "" `shouldBe` Left EmptyFilter
  for_
    [ ("空白", "blob:none tree:0")
    , ("NUL", "blob:none\0")
    , ("制御文字", "blob:none\ESC")
    ]
    \(name, value) ->
      it (name <> "を含むフィルタを拒否する") do
        parsePartialCloneFilter value `shouldBe` Left FilterUnsafeCharacter
