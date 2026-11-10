-- | コマンドライン引数からの実行と、終了の仕方のテスト。
module Spec.CliSpec (tests) where

import CertspotterMackerel.Cli (runWith)
import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.EventLog (appendEvent, readEvents)
import Data.Text (isInfixOf)
import Fixture
import Himari
import Test.Sandwich

-- | ログを端末へ出さずに集めて、結果と共に返す。
--
-- `ExitCode`の例外で終わった時も、それまでのログを見られるように結果は`Either`で返す。
runCapturing :: (MonadIO m) => Himari SimpleEnv a -> m (Either ExitCode a, [Text])
runCapturing action = do
  logs <- newIORef []
  result <-
    runSimpleEnvWith
      (\_ _ _ message -> modifyIORef' logs (<> [convert (fromLogStr message)]))
      (try action)
  (result,) <$> readIORef logs

-- | チェックの設定。systemdの状態確認は、ユニットを指定しないことで省く。
checkVariables :: Workspace -> [(Text, Text)]
checkVariables workspace =
  [ ("CERTSPOTTER_EVENTS_LOG", convert workspace.eventLogFile)
  , ("CERTSPOTTER_ALERT_WINDOW_SECONDS", "86400")
  ]

tests :: TopSpec
tests = describe "runWith" do
  describe "hook" do
    it "環境変数の通知をログへ記録して成功で終わる" do
      withWorkspace \workspace -> do
        let environment =
              [ ("CERTSPOTTER_EVENTS_LOG", convert workspace.eventLogFile)
              , ("EVENT", "discovered_cert")
              , ("SUMMARY", "cert discovered for ncaq.net")
              , ("ISSUER_DN", "CN=R12")
              , ("JSON_FILENAME", convert workspace.certificate)
              ]
        runCapturing (runWith (variables environment) ["hook"]) >>= (`shouldBe` (Right (), []))
        -- 時刻は実行のたびに変わるので揃えてから比べる。
        events <- readEvents workspace.eventLog
        retimed sampleEvent.time events `shouldBe` Just [sampleEvent]
    it "ログの指定が無ければ理由を出して1で終わる" do
      (result, logs) <- runCapturing (runWith (variables [("EVENT", "error")]) ["hook"])
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      filter (isInfixOf "CERTSPOTTER_EVENTS_LOG") logs `shouldBe` logs
  describe "check" do
    -- 結果はMackerelが読むものとして標準出力へ直接出るので、こちらのログには何も出ない。
    it "イベントが無ければ成功で終わる" do
      withWorkspace \workspace ->
        runCapturing (runWith (variables (checkVariables workspace)) ["check"])
          >>= (`shouldBe` (Right (), []))
    it "最近のイベントがあれば2で終わる" do
      withWorkspace \workspace -> do
        now <- liftIO getCurrentTime
        appendEvent workspace.eventLog sampleEvent{time = now}
        runCapturing (runWith (variables (checkVariables workspace)) ["check"])
          >>= (`shouldBe` (Left (ExitFailure 2), []))
    it "設定が揃わなければ3で終わる" do
      runCapturing (runWith (variables []) ["check"]) >>= (`shouldBe` (Left (ExitFailure 3), []))
    it "アラート期間が数でなければ3で終わる" do
      withWorkspace \workspace -> do
        let environment =
              [ ("CERTSPOTTER_EVENTS_LOG", convert workspace.eventLogFile)
              , ("CERTSPOTTER_ALERT_WINDOW_SECONDS", "not-a-number")
              ]
        runCapturing (runWith (variables environment) ["check"])
          >>= (`shouldBe` (Left (ExitFailure 3), []))
  it "知らないサブコマンドは1で終わる" do
    -- 使い方はoptparse-applicativeが標準エラー出力へ直接出すので、こちらのログには何も出ない。
    runCapturing (runWith (variables []) ["unknown"]) >>= (`shouldBe` (Left (ExitFailure 1), []))
