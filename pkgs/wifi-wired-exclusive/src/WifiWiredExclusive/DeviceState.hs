-- | NetworkManagerが報告するデバイスの状態。
module WifiWiredExclusive.DeviceState
  ( DeviceState (..)
  , parseDeviceState
  ) where

import Himari

data DeviceState
  = Connected
  | Connecting
  | Disconnected
  | -- | 判断に使わない状態。`unavailable`や`unmanaged`など。
    OtherState Text
  deriving stock (Eq, Show)

-- | 状態を読む。
--
-- 完全に一致するものだけを読む。
-- NetworkManagerは`connected (externally)`や`connecting (configuring)`のように、
-- 括弧で詳細を付けた状態も報告するが、それらは`OtherState`になる。
-- 外部が管理している接続や途中の段階にあるデバイスには手を出さない。
parseDeviceState :: Text -> DeviceState
parseDeviceState = \case
  "connected" -> Connected
  "connecting" -> Connecting
  "disconnected" -> Disconnected
  other -> OtherState other
