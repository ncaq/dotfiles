-- | 通知へ出す文字列の掃除のテスト。
--
-- CAとCTログ由来の値で、通知の行や見え方を崩せないことを固定する。
module Spec.SanitizeSpec (tests) where

import CertspotterMackerel.Sanitize (sanitize)
import Himari
import Test.Sandwich

cases :: [(String, Text, Text)]
cases =
  [ ("普通の文字はそのまま通す", "CN=R12, O=Let's Encrypt", "CN=R12, O=Let's Encrypt")
  , ("非ASCIIの文字もそのまま通す", "発行者 Ünïcode", "発行者 Ünïcode")
  , ("タブを空白にする", "a\tb", "a b")
  , ("改行を空白にする", "a\nb\r\nc", "a b  c")
  , ("NULを空白にする", "a\0b", "a b")
  , ("行区切り(U+2028)を空白にする", "a\x2028\&b", "a b")
  , ("段落区切り(U+2029)を空白にする", "a\x2029\&b", "a b")
  , ("右から左への上書き(U+202E)を空白にする", "a\x202E\&b", "a b")
  , ("ゼロ幅空白(U+200B)を空白にする", "a\x200B\&b", "a b")
  , ("BOM(U+FEFF)を空白にする", "a\xFEFF\&b", "a b")
  , ("空文字列は空のまま", "", "")
  ]

tests :: TopSpec
tests = describe "sanitize" do
  for_ cases \(name, input, expected) ->
    it name do
      sanitize input `shouldBe` expected
