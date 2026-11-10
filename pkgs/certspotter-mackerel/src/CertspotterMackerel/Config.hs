-- | 起動時に受け取る設定。環境変数から受け取る。
--
-- NixOSモジュールが包むラッパーが設定する。
--
-- * `CERTSPOTTER_EVENTS_LOG`: hookが追記してチェックが読むログのパス。
-- * `CERTSPOTTER_ALERT_WINDOW_SECONDS`: この秒数以内のイベントがあればチェックをCRITICALにする。
-- * `CERTSPOTTER_SERVICE_UNIT`: チェックが動いていることを確かめるsystemdのユニット。
--   無いか空ならば確かめない。
module CertspotterMackerel.Config
  ( CheckConfig (..)
  , eventLogFrom
  , checkConfigFrom
  ) where

import CertspotterMackerel.EventLogPath (EventLogPath (..))
import CertspotterMackerel.Failure (ConfigFailure (..))
import CertspotterMackerel.Seconds (parseSeconds)
import CertspotterMackerel.ServiceUnit (ServiceUnit (..))
import Himari

-- | チェックの設定。
data CheckConfig = CheckConfig
  { eventLog :: EventLogPath
  , alertWindow :: NominalDiffTime
  , serviceUnit :: Maybe ServiceUnit
  }
  deriving stock (Eq, Show)

-- | 環境変数を引く関数からログのパスを取り出す。hookが要る設定はこれだけである。
eventLogFrom :: (Text -> Maybe Text) -> Either ConfigFailure EventLogPath
eventLogFrom lookupVariable =
  EventLogPath . convert <$> require lookupVariable "CERTSPOTTER_EVENTS_LOG"

-- | 環境変数を引く関数からチェックの設定を組み立てる。
checkConfigFrom :: (Text -> Maybe Text) -> Either ConfigFailure CheckConfig
checkConfigFrom lookupVariable =
  CheckConfig
    <$> eventLogFrom lookupVariable
    <*> (require lookupVariable "CERTSPOTTER_ALERT_WINDOW_SECONDS" >>= alertWindow)
    <*> pure (ServiceUnit <$> present (lookupVariable "CERTSPOTTER_SERVICE_UNIT"))
 where
  alertWindow raw = maybe (Left (InvalidAlertWindow raw)) Right (parseSeconds raw)

-- | 空は無いのと同じに扱う。
present :: Maybe Text -> Maybe Text
present = mfilter (/= mempty)

-- | 必須の環境変数を引く。
require :: (Text -> Maybe Text) -> Text -> Either ConfigFailure Text
require lookupVariable name =
  maybe (Left (MissingVariable name)) Right (present (lookupVariable name))
