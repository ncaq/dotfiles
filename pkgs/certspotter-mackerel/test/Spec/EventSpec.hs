-- | ログの1行の形のテスト。
--
-- hookが書いた行をチェックがそのまま読めることと、
-- 外部由来の値に何が入っても1行に収まることを固定する。
module Spec.EventSpec (tests) where

import CertspotterMackerel.Event (Event (..))
import Data.Text (isInfixOf)
import Fixture
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "Event" do
  it "書いたものをそのまま読める" do
    eitherDecode (encode sampleEvent) `shouldBe` Right sampleEvent
  it "読めなかった理由も含めてそのまま読める" do
    let event = sampleEvent{dnsNames = [], dnsNamesError = Just "no such file"}
    eitherDecode (encode event) `shouldBe` Right event
  it "改行やタブを含んでも1行になる" do
    let event = sampleEvent{summary = "cert\tdiscovered\nfor ncaq.net", issuer = "CN=R12\r\nO=Evil"}
        line :: Text = convert (encode event)
    filter (`isInfixOf` line) ["\n", "\r", "\t"] `shouldBe` []
    eitherDecode (encode event) `shouldBe` Right event
  it "鍵はスネークケースで、読めなかった理由が無ければ鍵ごと出さない" do
    toJSON sampleEvent
      `shouldBe` [aesonQQ|{
        "time": "2023-11-14T22:13:20Z",
        "event": "discovered_cert",
        "summary": "cert discovered for ncaq.net",
        "dns_names": ["ncaq.net", "*.ncaq.net"],
        "issuer": "CN=R12"
      }|]
  it "読めなかった理由があればdns_names_errorとして出す" do
    toJSON sampleEvent{dnsNames = [], dnsNamesError = Just "no such file"}
      `shouldBe` [aesonQQ|{
        "time": "2023-11-14T22:13:20Z",
        "event": "discovered_cert",
        "summary": "cert discovered for ncaq.net",
        "dns_names": [],
        "issuer": "CN=R12",
        "dns_names_error": "no such file"
      }|]
  it "前の版が書いたUNIX時刻の秒の行も読む" do
    let line =
          [aesonQQ|{
            "time": 1700000000,
            "event": "discovered_cert",
            "summary": "cert discovered for ncaq.net",
            "dns_names": ["ncaq.net", "*.ncaq.net"],
            "issuer": "CN=R12"
          }|]
    eitherDecode (encode line) `shouldBe` Right sampleEvent
  it "時刻として読めない値は読まない" do
    isLeft (eitherDecode "{\"time\":\"yesterday\"}" :: Either String Event) `shouldBe` True
  it "時刻以外の鍵が無くても読む" do
    eitherDecode "{\"time\":\"1970-01-01T00:00:01Z\"}"
      `shouldBe` Right
        Event
          { time = posixSecondsToUTCTime 1
          , event = ""
          , summary = ""
          , dnsNames = []
          , issuer = ""
          , dnsNamesError = Nothing
          }
  it "時刻が無ければ読まない" do
    isLeft (eitherDecode "{\"event\":\"discovered_cert\"}" :: Either String Event) `shouldBe` True
