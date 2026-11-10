-- | certspotterが付ける、人が読むための要約。
--
-- 証明書の中身から作られるので、CAとCTログ由来の信頼できない値を含む。
module CertspotterMackerel.Summary
  ( Summary (..)
  ) where

import Himari

newtype Summary = Summary Text
  deriving stock (Eq, Show)
  deriving newtype (FromJSON, IsString, ToJSON)
