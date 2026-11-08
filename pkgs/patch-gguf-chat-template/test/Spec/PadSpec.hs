-- | `padToLength`のテスト。
--
-- 埋めた結果の長さだけでなく中身も固定する。
-- Jinjaのコメントとして閉じていなければ、描画の時に初めて壊れる。
module Spec.PadSpec (tests) where

import Data.ByteString qualified as B
import Himari
import PatchGgufChatTemplate.Pad
import Test.Sandwich

template :: ByteString
template = "{{- 'ok' }}"

tests :: TopSpec
tests = describe "padToLength" do
  it "長さが一致していれば何も足さない" do
    padToLength template (B.length template) `shouldBe` Right template
  it "4バイトちょうどなら空のコメントで埋まる" do
    padToLength template (B.length template + 4) `shouldBe` Right (template <> "{##}")
  it "余りは空白のコメントで埋める" do
    padToLength template (B.length template + 7) `shouldBe` Right (template <> "{#   #}")
  for_ [1, 2, 3] \padding ->
    it ("Jinjaのコメントに満たない" <> show padding <> "バイトの端数は埋められない") do
      padToLength template (B.length template + padding) `shouldBe` Left (PaddingTooSmall padding)
  it "元より長ければ超えた分を報告する" do
    padToLength template (B.length template - 3) `shouldBe` Left (TemplateTooLong 3)
