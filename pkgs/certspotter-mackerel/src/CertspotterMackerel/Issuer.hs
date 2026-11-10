-- | 証明書の発行者の識別名。
--
-- 証明書に書かれた値そのままで、CAとCTログ由来の信頼できない値である。
module CertspotterMackerel.Issuer
  ( Issuer (..)
  ) where

import Himari

newtype Issuer = Issuer Text
  deriving stock (Eq, Show)
  deriving newtype (FromJSON, IsString, ToJSON)
