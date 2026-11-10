-- | certspotterがhookへ渡す通知。環境変数から受け取る。
--
-- 環境変数の仕様は`man 8 certspotter-script`にある。
--
-- * `EVENT`: イベントの種類。
-- * `SUMMARY`: 人が読むための要約。
-- * `ISSUER_DN`: 発行者の識別名。
-- * `JSON_FILENAME`: 証明書の情報を書いたJSONファイルのパス。
module CertspotterMackerel.Notification
  ( Notification (..)
  , notificationFrom
  , hasCertificate
  ) where

import CertspotterMackerel.EventKind (EventKind (..), discoveredCert, unknownKind)
import CertspotterMackerel.Issuer (Issuer (..))
import CertspotterMackerel.Summary (Summary (..))
import Himari

data Notification = Notification
  { event :: EventKind
  , summary :: Summary
  , issuer :: Issuer
  , jsonFilename :: Maybe FilePath
  }
  deriving stock (Eq, Show)

-- | 環境変数を引く関数から通知を組み立てる。
--
-- 無い変数があっても失敗にはしない。
-- `discovered_cert`以外(`malformed_cert`や`error`)は一部の変数しか渡されないが、
-- それらも監視自体の異常なので記録したい。
notificationFrom :: (Text -> Maybe Text) -> Notification
notificationFrom lookupVariable =
  Notification
    { event = maybe unknownKind EventKind (lookupVariable "EVENT")
    , summary = Summary (fromMaybe "" (lookupVariable "SUMMARY"))
    , issuer = Issuer (fromMaybe "" (lookupVariable "ISSUER_DN"))
    , jsonFilename = convert <$> lookupVariable "JSON_FILENAME"
    }

-- | 証明書のJSONを伴う通知なら、そのパスを返す。
--
-- `JSON_FILENAME`が証明書を指すのは`discovered_cert`の時だけである。
hasCertificate :: Notification -> Maybe FilePath
hasCertificate notification = do
  guard (notification.event == discoveredCert)
  notification.jsonFilename
