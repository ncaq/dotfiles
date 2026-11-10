-- | 設定の環境変数の読み方のテスト。
--
-- 設定が揃わない時に、黙って既定値で動き出さないことを固定する。
module Spec.ConfigSpec (tests) where

import CertspotterMackerel.Config (CheckConfig (..), checkConfigFrom, eventLogFrom)
import CertspotterMackerel.Failure (ConfigFailure (..))
import Fixture
import Himari
import Test.Sandwich

-- | 揃っている設定。
complete :: [(Text, Text)]
complete =
  [ ("CERTSPOTTER_EVENTS_LOG", "/var/lib/certspotter/events.log")
  , ("CERTSPOTTER_ALERT_WINDOW_SECONDS", "86400")
  , ("CERTSPOTTER_SERVICE_UNIT", "certspotter.service")
  ]

-- | 揃っている設定のうち、1つの変数だけを差し替える。
with :: Text -> Text -> [(Text, Text)]
with name value = (name, value) : filter ((/= name) . fst) complete

-- | 揃っている設定から、1つの変数を取り除く。
lacking :: Text -> [(Text, Text)]
lacking name = filter ((/= name) . fst) complete

expected :: CheckConfig
expected =
  CheckConfig
    { eventLog = "/var/lib/certspotter/events.log"
    , alertWindow = 86400
    , serviceUnit = Just "certspotter.service"
    }

tests :: TopSpec
tests = do
  describe "eventLogFrom" do
    it "ログのパスを読む" do
      eventLogFrom (variables complete) `shouldBe` Right "/var/lib/certspotter/events.log"
    it "無ければ失敗にする" do
      eventLogFrom (variables []) `shouldBe` Left (MissingVariable "CERTSPOTTER_EVENTS_LOG")
    it "空は無いのと同じに扱う" do
      eventLogFrom (variables (with "CERTSPOTTER_EVENTS_LOG" ""))
        `shouldBe` Left (MissingVariable "CERTSPOTTER_EVENTS_LOG")
  describe "checkConfigFrom" do
    it "揃っていれば読む" do
      checkConfigFrom (variables complete) `shouldBe` Right expected
    it "ログのパスが無ければ失敗にする" do
      checkConfigFrom (variables (lacking "CERTSPOTTER_EVENTS_LOG"))
        `shouldBe` Left (MissingVariable "CERTSPOTTER_EVENTS_LOG")
    it "アラート期間が無ければ失敗にする" do
      checkConfigFrom (variables (lacking "CERTSPOTTER_ALERT_WINDOW_SECONDS"))
        `shouldBe` Left (MissingVariable "CERTSPOTTER_ALERT_WINDOW_SECONDS")
    for_ ["not-a-number", "1.5", "-1", "1h"] \raw ->
      it ("アラート期間が" <> show raw <> "なら失敗にする") do
        checkConfigFrom (variables (with "CERTSPOTTER_ALERT_WINDOW_SECONDS" raw))
          `shouldBe` Left (InvalidAlertWindow raw)
    it "アラート期間は0でも読む" do
      checkConfigFrom (variables (with "CERTSPOTTER_ALERT_WINDOW_SECONDS" "0"))
        `shouldBe` Right expected{alertWindow = 0}
    it "ユニットが無ければ確かめない設定になる" do
      checkConfigFrom (variables (lacking "CERTSPOTTER_SERVICE_UNIT"))
        `shouldBe` Right expected{serviceUnit = Nothing}
    it "ユニットが空でも確かめない設定になる" do
      checkConfigFrom (variables (with "CERTSPOTTER_SERVICE_UNIT" ""))
        `shouldBe` Right expected{serviceUnit = Nothing}
