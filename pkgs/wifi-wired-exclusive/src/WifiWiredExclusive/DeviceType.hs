-- | NetworkManagerが報告するデバイスの種類。
module WifiWiredExclusive.DeviceType
  ( DeviceType (..)
  , parseDeviceType
  ) where

import Himari

data DeviceType
  = -- | 物理的な有線。
    -- Tailscaleのtunや仮想NICは別の種類として報告されるので、ここには入らない。
    Ethernet
  | Wifi
  | -- | 判断に使わない種類。`tun`や`loopback`や`wifi-p2p`など。
    OtherType Text
  deriving stock (Eq, Show)

parseDeviceType :: Text -> DeviceType
parseDeviceType = \case
  "ethernet" -> Ethernet
  "wifi" -> Wifi
  other -> OtherType other
