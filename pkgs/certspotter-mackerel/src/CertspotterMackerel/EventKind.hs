-- | certspotterのイベントの種類。
--
-- `man 8 certspotter-script`にある`EVENT`の値である。
-- certspotterが将来種類を足しても記録できるように、列挙にはせず文字列のまま持つ。
module CertspotterMackerel.EventKind
  ( EventKind (..)
  , discoveredCert
  , monitoringError
  , unknownKind
  ) where

import Himari

newtype EventKind = EventKind Text
  deriving stock (Eq, Show)
  deriving newtype (FromJSON, IsString, ToJSON)

-- | 監視対象の名前を含む証明書が見つかった。証明書のJSONを伴うのはこの種類だけである。
discoveredCert :: EventKind
discoveredCert = "discovered_cert"

-- | certspotterが全てのCTログを監視できていない。
--
-- ヘルスチェックの失敗であり、CTログへ届かない、追従が遅れている、ログの一覧を取れない、のどれかである。
-- 証明書が発行されたことを意味しない。
monitoringError :: EventKind
monitoringError = "error"

-- | 種類が渡されなかった。
unknownKind :: EventKind
unknownKind = "unknown"
