-- | 証明書のSANに載っているDNS名。
--
-- CTログ由来の信頼できない値で、DNS名として正しい形をしている保証は無い。
-- 検証はせず、他の文字列と取り違えないように型だけを分ける。
module CertspotterMackerel.DnsName
  ( DnsName (..)
  ) where

import Himari

newtype DnsName = DnsName Text
  deriving stock (Eq, Show)
  deriving newtype (FromJSON, IsString, ToJSON)
