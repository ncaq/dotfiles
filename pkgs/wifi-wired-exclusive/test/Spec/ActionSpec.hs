-- | dispatcherのアクションの読み方のテスト。
module Spec.ActionSpec (tests) where

import Himari
import Test.Sandwich
import WifiWiredExclusive.Action (Action (..), parseAction, requestedAction)

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
tests = do
  describe "parseAction" do
    for_ cases \(raw, expected) ->
      it (show raw <> " -> " <> show expected) do
        parseAction raw `shouldBe` expected
  describe "requestedAction" do
    it "第2引数をアクションとして読む" do
      requestedAction ["wlp1s0", "up"] `shouldBe` Just InterfaceUp
    it "知らないアクションは読まない" do
      requestedAction ["wlp1s0", "pre-up"] `shouldBe` Nothing
    for_ [[], ["wlp1s0"], ["wlp1s0", "up", "extra"]] \argv ->
      it ("引数が" <> show argv <> "なら読まない") do
        requestedAction argv `shouldBe` Nothing
