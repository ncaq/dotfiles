-- | チェックの判定のテスト。
--
-- アラート期間の境界と、古いイベントを出さないことと、
-- 監視の不調だけではCRITICALにしないことを固定する。
module Spec.JudgeSpec (tests) where

import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.Judge (judge)
import CertspotterMackerel.Render (render)
import CertspotterMackerel.Status (Status (..))
import Fixture
import Himari
import Test.Sandwich

-- | 今の時刻。
now :: UTCTime
now = posixSecondsToUTCTime 1700000000

-- | アラート期間。
window :: NominalDiffTime
window = 86400

-- | 今から指定の秒数だけ前のイベント。
ago :: NominalDiffTime -> Event
ago seconds = sampleEvent{time = earlier seconds now}

-- | ログのイベントを判定する。
judged :: [Event] -> Status
judged = judge now window . Just

-- | 今から指定の秒数だけ前の、certspotterのヘルスチェックの失敗。
--
-- 追従できないCTログがあると、certspotterはヘルスチェックのたびにこの形で通知する。
backlogAgo :: NominalDiffTime -> Event
backlogAgo seconds =
  Event
    { time = earlier seconds now
    , event = "error"
    , summary = "Backlog of size 92920662 from https://eszigno2027h1.mon.ct.e-szigno.hu/"
    , dnsNames = []
    , issuer = ""
    , dnsNamesError = Nothing
    }

headline :: Text
headline = "certspotter CRITICAL: new certificate transparency events"

degradedHeadline :: Text
degradedHeadline = "certspotter WARNING: certificate transparency monitoring is degraded"

tests :: TopSpec
tests = describe "judge" do
  it "ログがまだ無ければOK" do
    judge now window Nothing `shouldBe` Ok "certspotter OK (no events yet)"
  it "ログが空ならOK" do
    judged [] `shouldBe` Ok "certspotter OK"
  it "アラート期間より古いイベントだけならOK" do
    judged [ago (window + 1), ago (2 * window)] `shouldBe` Ok "certspotter OK"
  it "アラート期間ちょうどのイベントはCRITICAL" do
    judged [ago window] `shouldBe` Critical [headline, render (ago window)]
  it "今のイベントはCRITICAL" do
    judged [ago 0] `shouldBe` Critical [headline, render (ago 0)]
  it "古いイベントと新しいイベントが混ざっていたら新しいものだけをログの順に出す" do
    judged [ago (2 * window), ago 100, ago (window + 1), ago 10]
      `shouldBe` Critical [headline, render (ago 100), render (ago 10)]
  it "時計が巻き戻って未来を指すイベントもCRITICAL" do
    judged [ago -100] `shouldBe` Critical [headline, render (ago -100)]
  it "アラート期間が0なら今のイベントだけをCRITICALにする" do
    judge now 0 (Just [ago 1, ago 0]) `shouldBe` Critical [headline, render (ago 0)]
  it "監視の不調だけならWARNING" do
    judged [backlogAgo 100, backlogAgo 10]
      `shouldBe` Warning [degradedHeadline, render (backlogAgo 100), render (backlogAgo 10)]
  it "アラート期間より古い監視の不調だけならOK" do
    judged [backlogAgo (window + 1)] `shouldBe` Ok "certspotter OK"
  it "監視の不調と証明書のイベントが混ざっていたらCRITICALにして、両方をログの順に出す" do
    judged [backlogAgo 100, ago 50, backlogAgo 10]
      `shouldBe` Critical [headline, render (backlogAgo 100), render (ago 50), render (backlogAgo 10)]
  it "古い証明書のイベントと新しい監視の不調ならWARNING" do
    judged [ago (window + 1), backlogAgo 10]
      `shouldBe` Warning [degradedHeadline, render (backlogAgo 10)]
  it "証明書の発見でも監視の不調でもない種類のイベントはCRITICAL" do
    let malformed = (ago 0){event = "malformed_cert"}
        unknown = (ago 0){event = "unknown"}
    judged [malformed, unknown] `shouldBe` Critical [headline, render malformed, render unknown]
