-- | systemdのユニットと、その状態の確認。
module CertspotterMackerel.ServiceUnit
  ( ServiceUnit (..)
  , serviceActive
  ) where

import Himari

-- | systemdのユニットの名前。`certspotter.service`など。
newtype ServiceUnit = ServiceUnit Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | ユニットが動いているか。
serviceActive :: (MonadIO m) => ServiceUnit -> m Bool
serviceActive (ServiceUnit unit) =
  (== ExitSuccess) <$> runProcess (proc "systemctl" ["is-active", "--quiet", convert unit])
