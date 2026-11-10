-- | `nmcli`の呼び出し。
--
-- 呼び出しを値として持つのは、テストで実際のNetworkManagerを触らずに済ませるためである。
module WifiWiredExclusive.Nmcli
  ( Nmcli (..)
  , systemNmcli
  ) where

import Himari
import WifiWiredExclusive.Operation (Operation, nmcliArguments)

data Nmcli m = Nmcli
  { listDevices :: m Text
  -- ^ 全デバイスの`DEVICE:TYPE:STATE`の一覧を取る。
  , perform :: Operation -> m ExitCode
  -- ^ 操作を行って、`nmcli`の終了コードを返す。
  }

-- | PATHにある`nmcli`を呼ぶ。
systemNmcli :: (MonadIO m) => Nmcli m
systemNmcli =
  Nmcli
    { listDevices =
        convert <$> readProcessStdout_ (proc "nmcli" ["-t", "-f", "DEVICE,TYPE,STATE", "device"])
    , perform = runProcess . proc "nmcli" . nmcliArguments
    }
