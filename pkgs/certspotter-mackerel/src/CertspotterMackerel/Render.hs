-- | イベントをMackerelの通知に出す1行にする。
module CertspotterMackerel.Render
  ( render
  ) where

import CertspotterMackerel.DnsName (DnsName (..))
import CertspotterMackerel.Event (Event (..))
import CertspotterMackerel.EventKind (EventKind (..))
import CertspotterMackerel.Issuer (Issuer (..))
import CertspotterMackerel.Sanitize (sanitize)
import CertspotterMackerel.Summary (Summary (..))
import Data.Text qualified as T
import Himari

-- | イベントを1行にする。
--
-- 外部由来の値は全て`sanitize`を通す。
-- `event`はcertspotterが決める値だが、ログが壊れていた時のために同じ方針で扱う。
render :: Event -> Text
render event =
  T.unwords $
    [ timestamp
    , sanitize kind <> ":"
    , sanitize summary
    , "(" <> sanitize (T.intercalate "," (coerce event.dnsNames)) <> ")"
    , "issuer=" <> sanitize issuer
    ]
      <> foldMap (\reason -> ["dns_names_error=" <> sanitize reason]) event.dnsNamesError
 where
  -- 秒までのUTCのISO 8601で出す。
  timestamp = convert (formatTime defaultTimeLocale "%FT%TZ" event.time)
  EventKind kind = event.event
  Summary summary = event.summary
  Issuer issuer = event.issuer
