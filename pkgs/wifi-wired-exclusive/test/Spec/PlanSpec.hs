-- | 操作の決め方のテスト。
--
-- 実機で確かめるには有線を抜き差しする必要があり、
-- 接続処理中のような途中の状態は狙って作れない。
-- 状態の組み合わせごとの操作をここで固定する。
module Spec.PlanSpec (tests) where

import Test.Sandwich
import WifiWiredExclusive.Device (Device (..))
import WifiWiredExclusive.DeviceState (DeviceState (..))
import WifiWiredExclusive.DeviceType (DeviceType (..))
import WifiWiredExclusive.Operation (Operation (..))
import WifiWiredExclusive.Plan (plan)

wired :: DeviceState -> Device
wired = Device "enp9s0" Ethernet

wifi :: DeviceState -> Device
wifi = Device "wlp8s0" Wifi

tests :: TopSpec
tests = describe "plan" do
  describe "有線が繋がっている時" do
    it "繋がっているWiFiは接続だけ切る" do
      plan [wired Connected, wifi Connected] `shouldBe` [Disconnect "wlp8s0"]
    it "接続処理中のWiFiも接続を切る" do
      plan [wired Connected, wifi Connecting] `shouldBe` [Disconnect "wlp8s0"]
    it "既に切れているWiFiには何もしない" do
      -- 切れているデバイスへの切断はエラーになる。
      plan [wired Connected, wifi Disconnected] `shouldBe` []
    it "使えないWiFiには何もしない" do
      plan [wired Connected, wifi (OtherState "unavailable")] `shouldBe` []
    it "デバイスの並び順に依らない" do
      plan [wifi Connected, wired Connected] `shouldBe` [Disconnect "wlp8s0"]
    it "WiFiが複数あればそれぞれ切る" do
      plan [wired Connected, wifi Connected, Device "wlp9s0" Wifi Connected]
        `shouldBe` [Disconnect "wlp8s0", Disconnect "wlp9s0"]
  describe "有線が繋がっていない時" do
    it "切れているWiFiは自動接続を戻して繋ぎ直す" do
      plan [wired (OtherState "unavailable"), wifi Disconnected]
        `shouldBe` [EnableAutoconnect "wlp8s0", Connect "wlp8s0"]
    it "接続処理中のWiFiは自動接続を戻すだけで、重ねて接続を要求しない" do
      -- 重ねて要求すると完了待ちで90秒ブロックし、無限ループになる。
      plan [wired Disconnected, wifi Connecting] `shouldBe` [EnableAutoconnect "wlp8s0"]
    it "繋がっているWiFiは自動接続を戻すだけ" do
      plan [wired Disconnected, wifi Connected] `shouldBe` [EnableAutoconnect "wlp8s0"]
    it "有線のデバイスが無くても同じ" do
      plan [wifi Disconnected] `shouldBe` [EnableAutoconnect "wlp8s0", Connect "wlp8s0"]
  describe "有線として数えないもの" do
    it "Tailscaleのtunが繋がっていても有線とはみなさない" do
      plan [Device "tailscale0" (OtherType "tun") Connected, wifi Connected]
        `shouldBe` [EnableAutoconnect "wlp8s0"]
    it "外部が管理している有線は繋がっているとはみなさない" do
      plan [wired (OtherState "connected (externally)"), wifi Connected]
        `shouldBe` [EnableAutoconnect "wlp8s0"]
  describe "WiFi以外" do
    it "WiFi Directのデバイスには手を出さない" do
      plan [wired Connected, Device "p2p-dev-wlp8s0" (OtherType "wifi-p2p") Connected]
        `shouldBe` []
    it "デバイスが無ければ何もしない" do
      plan [] `shouldBe` []
