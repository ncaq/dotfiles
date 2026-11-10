-- | WiFiのデバイスへ行う操作。
module WifiWiredExclusive.Operation
  ( Operation (..)
  , nmcliArguments
  ) where

import Himari
import WifiWiredExclusive.DeviceName (DeviceName (..))

data Operation
  = -- | 接続だけを切る。ラジオはオンのままにする。
    Disconnect DeviceName
  | -- | `Disconnect`で抑止された自動接続を解除する。
    EnableAutoconnect DeviceName
  | Connect DeviceName
  deriving stock (Eq, Show)

-- | 操作を行う`nmcli`の引数。
nmcliArguments :: Operation -> [String]
nmcliArguments = \case
  Disconnect (DeviceName name) -> ["device", "disconnect", convert name]
  EnableAutoconnect (DeviceName name) -> ["device", "set", convert name, "autoconnect", "yes"]
  Connect (DeviceName name) -> ["device", "connect", convert name]
