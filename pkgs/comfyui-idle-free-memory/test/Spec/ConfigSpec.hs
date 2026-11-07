-- | 設定の読み方のテスト。
--
-- 秒数の環境変数を起動時に厳しく検査する振る舞いを、境界値で固定する。
module Spec.ConfigSpec (tests) where

import Himari
import IdleFreeMemory.Config (parseSeconds)
import Test.Sandwich

cases :: [(String, Maybe Int)]
cases =
  [ ("300", Just 300)
  , ("1", Just 1)
  , -- 0秒の待ちは待たずに回り続ける。
    ("0", Nothing)
  , ("-1", Nothing)
  , ("1.5", Nothing)
  , ("1e3", Nothing)
  , ("", Nothing)
  , -- `Read`は前後の空白を読み飛ばすが、書き損じなので通さない。
    ("60 ", Nothing)
  , (" 60", Nothing)
  , ("+60", Nothing)
  , -- マイクロ秒にすると`Int`へ収まらない。
    ("9223372036855", Nothing)
  , -- `Int`として読むと桁あふれで正の値に化ける。
    ("18446744073709551917", Nothing)
  ]

tests :: TopSpec
tests = describe "parseSeconds" do
  for_ cases \(raw, expected) ->
    it (show raw <> " -> " <> show expected) do
      parseSeconds raw `shouldBe` expected
