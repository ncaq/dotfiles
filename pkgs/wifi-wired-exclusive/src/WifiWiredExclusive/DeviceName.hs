-- | ネットワークデバイスの名前。`wlp8s0`など。
module WifiWiredExclusive.DeviceName
  ( DeviceName (..)
  ) where

import Himari

newtype DeviceName = DeviceName Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)
