-- | ログのイベントからチェックの結果を決める。
--
-- 時刻は引数で受け取り、時計にもファイルにも触れない。
module CertspotterMackerel.Judge
  ( judge
  ) where

import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.Render (render)
import CertspotterMackerel.Status (Status (..))
import Himari

-- | アラート期間以内のイベントがあればCRITICALにする。
--
-- イベントは一度きりの出来事だが、期間の間はCRITICALのままにする。
-- アラートが一定期間開いたままになることで見落としを防ぐ。
judge
  :: UTCTime
  -- ^ 今の時刻。
  -> NominalDiffTime
  -- ^ アラート期間。
  -> Maybe [Event]
  -- ^ ログのイベント。ログがまだ無ければ`Nothing`。
  -> Status
judge _ _ Nothing = Ok "certspotter OK (no events yet)"
judge now alertWindow (Just events) =
  case filter (\event -> diffUTCTime now event.time <= alertWindow) events of
    [] -> Ok "certspotter OK"
    recent ->
      Critical ("certspotter CRITICAL: new certificate transparency events" : fmap render recent)
