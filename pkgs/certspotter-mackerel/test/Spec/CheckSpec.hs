-- | hookが書いたログをチェックが読む、一続きのテスト。
--
-- hookとチェックは別々のプロセスとして別々の時に動くので、
-- 片方だけを見ていると、書く形と読む形がずれても気付けない。
-- 本物と同じ関数で書いて読んで、結果を固定する。
--
-- systemdの状態確認は、ユニットを指定しないことで省く。
module Spec.CheckSpec (tests) where

import CertspotterMackerel.Check (check)
import CertspotterMackerel.Config (CheckConfig (..))
import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.EventLog (appendEvent)
import CertspotterMackerel.Hook (recordNotification)
import CertspotterMackerel.Notification (Notification (..))
import CertspotterMackerel.Status (Status (..))
import CertspotterMackerel.Summary (Summary)
import Data.Text (isInfixOf)
import Fixture
import Himari
import Test.Sandwich

-- | アラート期間。
window :: NominalDiffTime
window = 86400

configFor :: Workspace -> CheckConfig
configFor workspace =
  CheckConfig
    { eventLog = workspace.eventLog
    , alertWindow = window
    , serviceUnit = Nothing
    }

-- | 今から指定の秒数だけ前のイベントを、hookを通さずにログへ足す。
appendAgo :: (MonadUnliftIO m) => Workspace -> NominalDiffTime -> Summary -> m ()
appendAgo workspace seconds summary = do
  time <- earlier seconds <$> liftIO getCurrentTime
  appendEvent workspace.eventLog sampleEvent{time, summary}

-- | CRITICALの行。CRITICALでなければ空。
criticalLines :: Status -> [Text]
criticalLines = \case
  Critical messages -> messages
  _ -> []

tests :: TopSpec
tests = describe "check" do
  it "ログがまだ無ければOK" do
    withWorkspace \workspace ->
      check (configFor workspace) >>= (`shouldBe` Ok "certspotter OK (no events yet)")
  it "hookが記録したイベントを、見出しとイベントごとの1行でCRITICALにする" do
    withWorkspace \workspace -> do
      recordNotification workspace.eventLog (hostileNotification workspace.certificate)
      recordNotification
        workspace.eventLog
        Notification
          { event = "error"
          , summary = "log unreachable"
          , issuer = ""
          , jsonFilename = Nothing
          }
      -- `event`はcertspotterが決める値だが、ログが壊れた時にも1行に収まることを見る。
      time <- liftIO getCurrentTime
      appendEvent workspace.eventLog sampleEvent{time, event = "evil\nevent"}
      messages <- criticalLines <$> check (configFor workspace)
      length messages `shouldBe` 4
      filter (`elem` forbiddenCharacters) (foldMap convert messages) `shouldBe` []
      filter (isInfixOf "(ncaq.net,*.ncaq.net)") messages `shouldNotBe` []
      filter (isInfixOf "error: log unreachable") messages `shouldNotBe` []
  it "証明書のJSONを読めなかった理由を出力に出す" do
    withWorkspace \workspace -> do
      recordNotification
        workspace.eventLog
        Notification
          { event = "discovered_cert"
          , summary = "unreadable cert json"
          , issuer = ""
          , jsonFilename = Just (workspace.root </> "missing.json")
          }
      messages <- criticalLines <$> check (configFor workspace)
      length messages `shouldBe` 2
      filter (isInfixOf "dns_names_error=") messages `shouldNotBe` []
  it "アラート期間より古い行と壊れた行だけならOK" do
    withWorkspace \workspace -> do
      appendAgo workspace (2 * window) "old"
      liftIO (appendFile workspace.eventLogFile "not json\n")
      check (configFor workspace) >>= (`shouldBe` Ok "certspotter OK")
  it "古い行と新しい行が混ざっていたら新しい行だけを出す" do
    withWorkspace \workspace -> do
      appendAgo workspace (2 * window) "old"
      liftIO (appendFile workspace.eventLogFile "not json\n")
      appendAgo workspace 0 "fresh"
      messages <- criticalLines <$> check (configFor workspace)
      length messages `shouldBe` 2
      filter (isInfixOf "old") messages `shouldBe` []
      filter (isInfixOf "fresh") messages `shouldNotBe` []
