-- | dispatcherのアクションの読み方のテスト。
module Spec.ActionSpec (tests) where

import Himari
import TailscaleExitNode.Action (Action (..), parseAction)
import Test.Sandwich

cases :: [(Text, Maybe Action)]
cases =
  [ ("up", Just InterfaceUp)
  , ("down", Nothing)
  , ("pre-up", Nothing)
  , ("connectivity-change", Nothing)
  , ("UP", Nothing)
  , ("", Nothing)
  ]

tests :: TopSpec
tests = describe "parseAction" do
  for_ cases \(raw, expected) ->
    it (show raw <> " -> " <> show expected) do
      parseAction raw `shouldBe` expected
