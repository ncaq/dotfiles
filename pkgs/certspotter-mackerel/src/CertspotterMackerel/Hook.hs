-- | certspotterのhookとして、通知をイベントのログへ記録する。
module CertspotterMackerel.Hook
  ( recordNotification
  , toEvent
  ) where

import CertspotterMackerel.Certificate (Certificate (..), readCertificate)
import CertspotterMackerel.DnsName (DnsName)
import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.EventLog (appendEvent)
import CertspotterMackerel.EventLogPath (EventLogPath)
import CertspotterMackerel.Notification (Notification (..), hasCertificate)
import Himari

-- | 通知を今の時刻のイベントにして、ログへ足す。
recordNotification :: (MonadUnliftIO m) => EventLogPath -> Notification -> m ()
recordNotification eventLog notification =
  (toEvent notification <$> liftIO getCurrentTime <*> dnsNames) >>= appendEvent eventLog
 where
  dnsNames = case hasCertificate notification of
    Just path -> fmap (.dnsNames) <$> readCertificate path
    Nothing -> pure (Right [])

-- | 通知と時刻とSANの読み取り結果からイベントを作る。
--
-- SANを読めなかった時は空にして、理由を握り潰さずに同じイベントへ残す。
toEvent :: Notification -> UTCTime -> Either Text [DnsName] -> Event
toEvent notification time dnsNamesResult =
  Event
    { time
    , event = notification.event
    , summary = notification.summary
    , dnsNames = fromRight [] dnsNamesResult
    , issuer = notification.issuer
    , dnsNamesError = dnsNamesResult ^? _Left
    }
