-- | dispatcherのアクションの読み方のテスト。
module Spec.ActionSpec (tests) where

import Himari
import Test.Sandwich
import WifiWiredExclusive.Action (Action (..), parseAction)

cases :: [(Text, Maybe Action)]
cases =
  [ ("up", Just InterfaceUp)
  , ("down", Just InterfaceDown)
  , ("pre-up", Nothing)
  , ("pre-down", Nothing)
  , ("dhcp4-change", Nothing)
  , ("connectivity-change", Nothing)
  , ("UP", Nothing)
  , ("", Nothing)
  ]

tests :: TopSpec
tests = describe "parseAction" do
  for_ cases \(raw, expected) ->
    it (show raw <> " -> " <> show expected) do
      parseAction raw `shouldBe` expected
