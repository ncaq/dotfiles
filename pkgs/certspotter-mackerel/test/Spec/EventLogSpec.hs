-- | ログの読み書きのテスト。
module Spec.EventLogSpec (tests) where

import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.EventLog (appendEvent, parseEvents, readEvents)
import Fixture
import Himari
import Test.Sandwich

tests :: TopSpec
tests = do
  describe "parseEvents" do
    it "1行に1つのイベントを読む" do
      parseEvents "{\"time\":1}\n{\"time\":2}\n" `shouldBe` [blank 1, blank 2]
    it "末尾に改行が無くても読む" do
      parseEvents "{\"time\":1}\n{\"time\":2}" `shouldBe` [blank 1, blank 2]
    it "壊れた行と空行は飛ばして残りを読む" do
      parseEvents "{\"time\":1}\nnot json\n\n{\"time\":\n{\"time\":2}\n"
        `shouldBe` [blank 1, blank 2]
    it "空のログからは何も読まない" do
      parseEvents "" `shouldBe` []
  describe "readEvents" do
    it "ログがまだ無ければNothingを返す" do
      withWorkspace \workspace -> readEvents workspace.eventLog >>= (`shouldBe` Nothing)
    it "足した順に読む" do
      withWorkspace \workspace -> do
        let second = sampleEvent{time = posixSecondsToUTCTime 1700000001, summary = "line\nbreak"}
        appendEvent workspace.eventLog sampleEvent
        appendEvent workspace.eventLog second
        readEvents workspace.eventLog >>= (`shouldBe` Just [sampleEvent, second])
 where
  blank seconds =
    Event
      { time = posixSecondsToUTCTime seconds
      , event = ""
      , summary = ""
      , dnsNames = []
      , issuer = ""
      , dnsNamesError = Nothing
      }
