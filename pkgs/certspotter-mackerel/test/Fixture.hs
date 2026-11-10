-- | テストで共有する値と、一時的な置き場所。
module Fixture
  ( variables
  , sampleEvent
  , earlier
  , retimed
  , hostileNotification
  , forbiddenCharacters
  , withWorkspace
  , Workspace (..)
  ) where

import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.EventLogPath (EventLogPath (..))
import CertspotterMackerel.Notification (Notification (..))
import Himari

-- | 連想リストを、環境変数を引く関数にする。
variables :: [(Text, Text)] -> Text -> Maybe Text
variables = flip lookup

-- | 2023-11-14T22:13:20Zのイベント。
sampleEvent :: Event
sampleEvent =
  Event
    { time = posixSecondsToUTCTime 1700000000
    , event = "discovered_cert"
    , summary = "cert discovered for ncaq.net"
    , dnsNames = ["ncaq.net", "*.ncaq.net"]
    , issuer = "CN=R12"
    , dnsNamesError = Nothing
    }

-- | 指定の長さだけ前の時刻。
earlier :: NominalDiffTime -> UTCTime -> UTCTime
earlier seconds = addUTCTime (negate seconds)

-- | 読んだイベントの時刻を全て同じ値に揃える。
--
-- hookが記録する時刻は実行のたびに変わるので、他の値を比べる前に揃える。
retimed :: UTCTime -> Maybe [Event] -> Maybe [Event]
retimed time = fmap (fmap (\event -> (event :: Event){time}))

-- | 通知の見え方を崩す文字。
--
-- タブと改行に加えて、行区切り(U+2028)と双方向制御(U+202E)とゼロ幅空白(U+200B)を含む。
forbiddenCharacters :: [Char]
forbiddenCharacters = ['\t', '\n', '\x2028', '\x202E', '\x200B']

-- | 見え方を崩す文字を`summary`と`issuer`へ混ぜた通知。
hostileNotification :: FilePath -> Notification
hostileNotification certificatePath =
  Notification
    { event = "discovered_cert"
    , summary = "cert\tdiscovered\nfor\x2028ncaq.net\x202E"
    , issuer = "CN=R12\tO=Evil\x200B"
    , jsonFilename = Just certificatePath
    }

-- | テストごとの一時的な置き場所。
data Workspace = Workspace
  { root :: FilePath
  , eventLogFile :: FilePath
  -- ^ まだ無いログのパス。
  , eventLog :: EventLogPath
  -- ^ `eventLogFile`と同じパス。
  , certificate :: FilePath
  -- ^ `ncaq.net`と`*.ncaq.net`をSANに持つ証明書のJSON。
  }

-- | 一時ディレクトリを作って、終わったら消す。
withWorkspace :: (MonadUnliftIO m) => (Workspace -> m a) -> m a
withWorkspace action =
  withSystemTempDirectory "certspotter-mackerel-test" \root -> do
    let certificate = root </> "cert.json"
        eventLogFile = root </> "events.log"
    liftIO (writeFile certificate "{\"dns_names\":[\"ncaq.net\",\"*.ncaq.net\"]}")
    action Workspace{root, eventLogFile, eventLog = EventLogPath eventLogFile, certificate}
