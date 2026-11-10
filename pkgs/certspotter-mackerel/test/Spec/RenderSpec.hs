-- | イベントを通知の1行にする形のテスト。
module Spec.RenderSpec (tests) where

import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.Render (render)
import Fixture
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "render" do
  it "時刻と種類と要約とSANと発行者を1行に並べる" do
    render sampleEvent
      `shouldBe` ( "2023-11-14T22:13:20Z discovered_cert: cert discovered for ncaq.net"
                     <> " (ncaq.net,*.ncaq.net) issuer=CN=R12"
                 )
  it "読めなかった理由があれば末尾に足す" do
    render sampleEvent{dnsNames = [], dnsNamesError = Just "no such file"}
      `shouldBe` ( "2023-11-14T22:13:20Z discovered_cert: cert discovered for ncaq.net"
                     <> " () issuer=CN=R12 dns_names_error=no such file"
                 )
  it "どの値に見え方を崩す文字があっても出さない" do
    let hostile :: (IsString a) => a
        hostile = "a\tb\nc\x2028\&d\x202E\&e\x200B\&f"
        line =
          render
            sampleEvent
              { event = hostile
              , summary = hostile
              , dnsNames = [hostile, hostile]
              , issuer = hostile
              , dnsNamesError = Just hostile
              }
    filter (`elem` forbiddenCharacters) (convert line) `shouldBe` []
