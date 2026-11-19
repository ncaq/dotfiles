-- | 今の環境から集める、適用の仕方を決めるための事実。
--
-- 集めることと判別することを分けるのは、判別をテストで固定するためである。
module DotfilesInstall.Probe
  ( Probe (..)
  , probe
  ) where

import Himari
import System.Posix.Unistd (SystemID (..), getSystemID)

data Probe = Probe
  { isNixos :: Bool
  -- ^ `/etc/NIXOS`があるか。
  , isTermux :: Bool
  -- ^ 環境変数`TERMUX_VERSION`が空ではない値で設定されているか。
  , hostName :: Text
  -- ^ `uname`の`nodename`。`hostname`コマンドが出すものと同じ。
  , machineName :: Text
  -- ^ `uname`の`machine`。
  }
  deriving stock (Eq, Show)

-- | 今の環境を調べる。
probe :: (MonadIO m) => m Probe
probe =
  fromSystemId
    <$> doesFileExist "/etc/NIXOS"
    <*> ((`notElem` [Nothing, Just ""]) <$> lookupEnv "TERMUX_VERSION")
    <*> liftIO getSystemID
 where
  -- `uname`は1回だけ呼んで、その結果から2つのフィールドを作る。
  fromSystemId isNixos isTermux systemId =
    Probe
      { isNixos
      , isTermux
      , hostName = convert systemId.nodeName
      , machineName = convert systemId.machine
      }
