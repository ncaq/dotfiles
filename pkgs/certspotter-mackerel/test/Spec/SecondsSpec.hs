-- | 秒数の読み方のテスト。
module Spec.SecondsSpec (tests) where

import CertspotterMackerel.Seconds (parseSeconds)
import Himari
import Test.Sandwich

cases :: [(Text, Maybe NominalDiffTime)]
cases =
  [ ("86400", Just 86400)
  , ("0", Just 0)
  , -- 負の長さは意味を持たない。
    ("-1", Nothing)
  , ("1.5", Nothing)
  , ("1h", Nothing)
  , ("not-a-number", Nothing)
  , ("", Nothing)
  ]

tests :: TopSpec
tests = describe "parseSeconds" do
  for_ cases \(raw, expected) ->
    it (show raw <> " -> " <> show expected) do
      parseSeconds raw `shouldBe` expected
