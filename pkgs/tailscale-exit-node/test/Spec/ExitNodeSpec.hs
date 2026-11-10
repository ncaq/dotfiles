-- | exit nodeの決め方のテスト。
module Spec.ExitNodeSpec (tests) where

import Himari
import TailscaleExitNode.ExitNode (ExitNode (..), chooseExitNode, setArguments)
import Test.Sandwich

cases :: [(String, Maybe NominalDiffTime, ExitNode)]
cases =
  [ ("0秒ならローカルとみなして直接通信する", Just 0, Direct)
  , ("4ミリ秒ならローカルとみなして直接通信する", Just 0.004, Direct)
  , ("しきい値ちょうどの10ミリ秒はローカルとみなす", Just 0.01, Direct)
  , ("11ミリ秒なら外部とみなして自宅サーバを経由する", Just 0.011, Via "seminar")
  , ("38ミリ秒なら外部とみなす", Just 0.038, Via "seminar")
  , ("1秒以上なら外部とみなす", Just 1.234, Via "seminar")
  , ("測れなかった時は外部とみなす", Nothing, Via "seminar")
  ]

tests :: TopSpec
tests = do
  describe "chooseExitNode" do
    for_ cases \(name, latency, expected) ->
      it name do
        chooseExitNode "seminar" latency `shouldBe` expected
  describe "setArguments" do
    it "直接通信する時はexit nodeを空にする" do
      setArguments Direct `shouldBe` ["set", "--exit-node="]
    it "経由する時はノード名を指定する" do
      setArguments (Via "seminar") `shouldBe` ["set", "--exit-node=seminar"]
