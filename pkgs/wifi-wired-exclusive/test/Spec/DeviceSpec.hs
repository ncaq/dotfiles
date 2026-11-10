-- | `nmcli`の出力の読み方のテスト。
module Spec.DeviceSpec (tests) where

import Data.Text qualified as T
import Test.Sandwich
import WifiWiredExclusive.Device (Device (..), parseDevices, splitFields)
import WifiWiredExclusive.DeviceState (DeviceState (..))
import WifiWiredExclusive.DeviceType (DeviceType (..))

tests :: TopSpec
tests = do
  describe "parseDevices" do
    it "実機の出力を読む" do
      parseDevices
        ( T.unlines
            [ "enp9s0:ethernet:connected"
            , "tailscale0:tun:connected (externally)"
            , "lo:loopback:connected (externally)"
            , "wlp8s0:wifi:disconnected"
            , "p2p-dev-wlp8s0:wifi-p2p:disconnected"
            ]
        )
        `shouldBe` [ Device "enp9s0" Ethernet Connected
                   , Device "tailscale0" (OtherType "tun") (OtherState "connected (externally)")
                   , Device "lo" (OtherType "loopback") (OtherState "connected (externally)")
                   , Device "wlp8s0" Wifi Disconnected
                   , Device "p2p-dev-wlp8s0" (OtherType "wifi-p2p") Disconnected
                   ]
    it "詳細の付いた接続中は判断に使わない状態として読む" do
      parseDevices "wlp8s0:wifi:connecting (configuring)\n"
        `shouldBe` [Device "wlp8s0" Wifi (OtherState "connecting (configuring)")]
    it "欄が足りない行と多い行は飛ばす" do
      parseDevices "wlp8s0:wifi\n\nenp9s0:ethernet:connected:extra\nwlp8s0:wifi:connected\n"
        `shouldBe` [Device "wlp8s0" Wifi Connected]
    it "空の出力からは何も読まない" do
      parseDevices "" `shouldBe` []
  describe "splitFields" do
    it "コロンで欄に分ける" do
      splitFields "a:b:c" `shouldBe` ["a", "b", "c"]
    it "エスケープされたコロンは値の一部として読む" do
      splitFields "eth0\\:1:ethernet:connected" `shouldBe` ["eth0:1", "ethernet", "connected"]
    it "エスケープされたバックスラッシュは値の一部として読む" do
      splitFields "a\\\\b:c" `shouldBe` ["a\\b", "c"]
    it "空の欄も欄として数える" do
      splitFields "a::c" `shouldBe` ["a", "", "c"]
