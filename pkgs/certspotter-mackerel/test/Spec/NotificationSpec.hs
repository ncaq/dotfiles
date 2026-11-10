-- | certspotterが渡す環境変数の読み方のテスト。
module Spec.NotificationSpec (tests) where

import CertspotterMackerel.Notification (Notification (..), hasCertificate, notificationFrom)
import Fixture
import Himari
import Test.Sandwich

discovered :: Notification
discovered =
  Notification
    { event = "discovered_cert"
    , summary = "cert discovered for ncaq.net"
    , issuer = "CN=R12"
    , jsonFilename = Just "/var/lib/certspotter/certs/aa/cert.json"
    }

tests :: TopSpec
tests = do
  describe "notificationFrom" do
    it "渡された環境変数をそのまま読む" do
      notificationFrom
        ( variables
            [ ("EVENT", "discovered_cert")
            , ("SUMMARY", "cert discovered for ncaq.net")
            , ("ISSUER_DN", "CN=R12")
            , ("JSON_FILENAME", "/var/lib/certspotter/certs/aa/cert.json")
            ]
        )
        `shouldBe` discovered
    it "何も渡されなくても失敗にしない" do
      -- 記録を止めるより、分からないイベントとして残す。
      notificationFrom (variables [])
        `shouldBe` discovered{event = "unknown", summary = "", issuer = "", jsonFilename = Nothing}
  describe "hasCertificate" do
    it "discovered_certなら証明書のパスを返す" do
      hasCertificate discovered `shouldBe` discovered.jsonFilename
    it "discovered_cert以外ではパスがあっても証明書として読まない" do
      hasCertificate discovered{event = "error"} `shouldBe` Nothing
    it "パスが無ければ読まない" do
      hasCertificate discovered{jsonFilename = Nothing} `shouldBe` Nothing
