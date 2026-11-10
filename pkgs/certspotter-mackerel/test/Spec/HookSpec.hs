-- | hookの記録のテスト。
--
-- 証明書のJSONが読めなくても落ちずにイベントを残すことを固定する。
module Spec.HookSpec (tests) where

import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.EventLog (readEvents)
import CertspotterMackerel.Hook (recordNotification, toEvent)
import CertspotterMackerel.Notification (Notification (..))
import Fixture
import Himari
import Test.Sandwich

-- | 記録して、ログのイベントを返す。時刻は実行のたびに変わるので0に揃える。
recorded :: (MonadUnliftIO m) => Workspace -> Notification -> m (Maybe [Event])
recorded workspace notification = do
  recordNotification workspace.eventLog notification
  retimed (posixSecondsToUTCTime 0) <$> readEvents workspace.eventLog

discovered :: Workspace -> Notification
discovered workspace =
  Notification
    { event = "discovered_cert"
    , summary = "cert discovered for ncaq.net"
    , issuer = "CN=R12"
    , jsonFilename = Just workspace.certificate
    }

tests :: TopSpec
tests = do
  describe "toEvent" do
    it "SANを読めたらそのまま持つ" do
      toEvent (discovered' Nothing) sampleEvent.time (Right ["ncaq.net", "*.ncaq.net"])
        `shouldBe` sampleEvent
    it "SANを読めなかったら空にして理由を残す" do
      toEvent (discovered' Nothing) sampleEvent.time (Left "no such file")
        `shouldBe` sampleEvent{dnsNames = [], dnsNamesError = Just "no such file"}
  describe "recordNotification" do
    it "証明書のSANと共に記録する" do
      withWorkspace \workspace ->
        recorded workspace (discovered workspace)
          >>= (`shouldBe` Just [sampleEvent{time = posixSecondsToUTCTime 0}])
    it "今の時刻で記録する" do
      withWorkspace \workspace -> do
        earliest <- liftIO getCurrentTime
        recordNotification workspace.eventLog (discovered workspace)
        latest <- liftIO getCurrentTime
        times <- foldMap (fmap (.time)) <$> readEvents workspace.eventLog
        fmap (\time -> earliest <= time && time <= latest) times `shouldBe` [True]
    it "見え方を崩す文字を含んでも1件として記録して、そのまま読み戻せる" do
      withWorkspace \workspace -> do
        let notification = hostileNotification workspace.certificate
        recorded workspace notification
          >>= ( `shouldBe`
                  Just
                    [ sampleEvent
                        { time = posixSecondsToUTCTime 0
                        , summary = notification.summary
                        , issuer = notification.issuer
                        }
                    ]
              )
    it "discovered_cert以外は証明書を読まずに記録する" do
      withWorkspace \workspace -> do
        let notification =
              Notification
                { event = "error"
                , summary = "log unreachable"
                , issuer = ""
                , jsonFilename = Just (workspace.root </> "missing.json")
                }
        recorded workspace notification
          >>= ( `shouldBe`
                  Just
                    [ Event
                        { time = posixSecondsToUTCTime 0
                        , event = "error"
                        , summary = "log unreachable"
                        , dnsNames = []
                        , issuer = ""
                        , dnsNamesError = Nothing
                        }
                    ]
              )
    for_ unreadable \(name, content) ->
      it ("証明書のJSONが" <> name <> "落ちずに、SANを空にして理由を残す") do
        withWorkspace \workspace -> do
          let path = workspace.root </> "unreadable.json"
          for_ content (liftIO . writeFile path)
          events <- recorded workspace (discovered workspace){jsonFilename = Just path}
          fmap (fmap (.dnsNames)) events `shouldBe` Just [[]]
          fmap (fmap (isJust . (.dnsNamesError))) events `shouldBe` Just [True]
    it "呼ばれるたびに1行ずつ足す" do
      withWorkspace \workspace -> do
        replicateM_ 3 (recordNotification workspace.eventLog (discovered workspace))
        events <- readEvents workspace.eventLog
        fmap length events `shouldBe` Just 3
 where
  discovered' jsonFilename =
    Notification
      { event = "discovered_cert"
      , summary = "cert discovered for ncaq.net"
      , issuer = "CN=R12"
      , jsonFilename
      }
  -- 中身が`Nothing`ならファイルを作らない。
  unreadable :: [(String, Maybe String)]
  unreadable =
    [ ("無くても", Nothing)
    , ("壊れていても", Just "not json")
    , ("配列ではないdns_namesを持っていても", Just "{\"dns_names\":\"ncaq.net\"}")
    ]
