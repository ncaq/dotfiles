-- | 今の環境から集める、適用の仕方を決めるための事実。
--
-- 集めることと判別することを分けるのは、判別をテストで固定するためである。
module DotfilesInstall.Probe
  ( Probe (..)
  , probe
  ) where

import Himari
import System.Posix.Unistd (getSystemID, machine, nodeName)

data Probe = Probe
  { isNixos :: Bool
  -- ^ `/etc/NIXOS`があるか。
  , isTermux :: Bool
  -- ^ 環境変数`TERMUX_VERSION`が空ではない値で設定されているか。
  , hostName :: String
  -- ^ `uname`の`nodename`。`hostname`コマンドが出すものと同じ。
  , machineName :: String
  -- ^ `uname`の`machine`。
  }
  deriving stock (Eq, Show)

-- | 今の環境を調べる。
probe :: (MonadIO m) => m Probe
probe =
  Probe
    <$> doesFileExist "/etc/NIXOS"
    <*> ((`notElem` [Nothing, Just ""]) <$> lookupEnv "TERMUX_VERSION")
    <*> (nodeName <$> systemId)
    <*> (machine <$> systemId)
 where
  systemId = liftIO getSystemID
