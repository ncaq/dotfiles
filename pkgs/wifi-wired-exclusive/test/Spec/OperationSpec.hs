-- | 操作を行う`nmcli`の引数のテスト。
module Spec.OperationSpec (tests) where

import Test.Sandwich
import WifiWiredExclusive.Operation (Operation (..), nmcliArguments)

tests :: TopSpec
tests = describe "nmcliArguments" do
  it "切断はラジオではなくデバイスの接続を切る" do
    nmcliArguments (Disconnect "wlp8s0") `shouldBe` ["device", "disconnect", "wlp8s0"]
  it "自動接続を有効に戻す" do
    nmcliArguments (EnableAutoconnect "wlp8s0")
      `shouldBe` ["device", "set", "wlp8s0", "autoconnect", "yes"]
  it "デバイスを接続する" do
    nmcliArguments (Connect "wlp8s0") `shouldBe` ["device", "connect", "wlp8s0"]
