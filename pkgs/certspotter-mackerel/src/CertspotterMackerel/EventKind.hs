-- | certspotterのイベントの種類。
--
-- `man 8 certspotter-script`にある`EVENT`の値である。
-- certspotterが将来種類を足しても記録できるように、列挙にはせず文字列のまま持つ。
module CertspotterMackerel.EventKind
  ( EventKind (..)
  , discoveredCert
  , unknownKind
  ) where

import Himari

newtype EventKind = EventKind Text
  deriving stock (Eq, Show)
  deriving newtype (FromJSON, IsString, ToJSON)

-- | 監視対象の名前を含む証明書が見つかった。証明書のJSONを伴うのはこの種類だけである。
discoveredCert :: EventKind
discoveredCert = "discovered_cert"

-- | 種類が渡されなかった。
unknownKind :: EventKind
unknownKind = "unknown"
