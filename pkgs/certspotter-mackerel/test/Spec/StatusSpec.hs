-- | Mackerelへ結果を伝える形のテスト。
module Spec.StatusSpec (tests) where

import CertspotterMackerel.Status (Status (..), statusExitCode, statusLines)
import Himari
import Test.Sandwich

tests :: TopSpec
tests = do
  describe "statusExitCode" do
    it "OKは0" do
      statusExitCode (Ok "ok") `shouldBe` ExitSuccess
    it "CRITICALは2" do
      statusExitCode (Critical ["critical"]) `shouldBe` ExitFailure 2
    it "UNKNOWNは3" do
      statusExitCode (Unknown "unknown") `shouldBe` ExitFailure 3
  describe "statusLines" do
    it "OKはメッセージの1行" do
      statusLines (Ok "ok") `shouldBe` ["ok"]
    it "CRITICALは見出しとイベントごとの行" do
      statusLines (Critical ["headline", "first"]) `shouldBe` ["headline", "first"]
    it "UNKNOWNはメッセージの1行" do
      statusLines (Unknown "unknown") `shouldBe` ["unknown"]
