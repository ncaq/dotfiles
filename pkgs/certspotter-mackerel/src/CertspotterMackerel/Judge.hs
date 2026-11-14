-- | ログのイベントからチェックの結果を決める。
--
-- 時刻は引数で受け取り、時計にもファイルにも触れない。
module CertspotterMackerel.Judge
  ( judge
  ) where

import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.EventKind (monitoringError)
import CertspotterMackerel.Render (render)
import CertspotterMackerel.Status (Status (..))
import Himari

-- | アラート期間以内のイベントがあれば、その種類に応じてWARNINGかCRITICALにする。
--
-- イベントは一度きりの出来事だが、期間の間は結果を保つ。
-- アラートが一定期間開いたままになることで見落としを防ぐ。
--
-- 監視の不調(`error`)だけならWARNINGにする。
-- certspotterは追従できないCTログが1つあるだけで、ヘルスチェックのたびにこれを通知する。
-- 証明書が発行されたわけではなく、こちらで直せないCTログ側の遅さでも起きるので、
-- 証明書の発見と同じCRITICALにすると、本当に確かめるべき通知が埋もれてしまう。
--
-- それ以外の種類が1つでもあればCRITICALにする。
-- 知らない種類を軽く扱うより、確かめる側へ倒す。
-- その時は監視の不調も一緒に出す。監視が欠けている最中の発見であることも判断の材料になる。
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
    recent
      | all (\event -> event.event == monitoringError) recent ->
          Warning
            ( "certspotter WARNING: certificate transparency monitoring is degraded"
                : fmap render recent
            )
      | otherwise ->
          Critical
            ("certspotter CRITICAL: new certificate transparency events" : fmap render recent)
