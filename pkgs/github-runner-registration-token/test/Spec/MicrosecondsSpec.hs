-- | 時間の長さのマイクロ秒への変換のテスト。
module Spec.MicrosecondsSpec (tests) where

import GithubRunnerRegistrationToken.Microseconds (microseconds)
import Test.Sandwich

tests :: TopSpec
tests = describe "microseconds" do
  it "秒をマイクロ秒にする" do
    microseconds 60 `shouldBe` 60000000
  it "1秒より短い長さも変換する" do
    microseconds 0.25 `shouldBe` 250000
  it "0は0にする" do
    microseconds 0 `shouldBe` 0
