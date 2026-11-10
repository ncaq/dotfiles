-- | Mackerelのチェックとして、certspotterの状態とイベントのログを調べる。
module CertspotterMackerel.Check
  ( check
  ) where

import CertspotterMackerel.Config (CheckConfig (..))
import CertspotterMackerel.EventLog (readEvents)
import CertspotterMackerel.Judge (judge)
import CertspotterMackerel.ServiceUnit (serviceActive)
import CertspotterMackerel.Status (Status (..))
import Himari

-- | チェックの結果を決める。
--
-- certspotterが止まっていると新しいイベントは永久に来ないので、
-- ログを見る前にサービスが動いていることを確かめる。
check :: (MonadIO m) => CheckConfig -> m Status
check config = do
  active <- maybe (pure True) serviceActive config.serviceUnit
  if active
    then judge <$> liftIO getCurrentTime <*> pure config.alertWindow <*> readEvents config.eventLog
    else pure (Critical ["certspotter CRITICAL: service not running"])
