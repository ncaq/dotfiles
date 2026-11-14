-- | 設定を適用する先の環境の種類。
module DotfilesInstall.Platform
  ( Platform (..)
  , detectPlatform
  ) where

import DotfilesInstall.Architecture (Architecture, parseArchitecture)
import DotfilesInstall.Failure (UnsupportedArchitecture)
import DotfilesInstall.Probe (Probe (..))
import Himari

data Platform
  = -- | NixOS。そのホスト名。
    NixOS String
  | -- | Termuxの上のNix-on-Droid。
    NixOnDroid
  | -- | その他のLinux。home-managerだけを適用する。
    HomeManager Architecture
  deriving stock (Eq, Show)

-- | 集めた事実から環境の種類を決める。
--
-- NixOS、Termux、その他の順に見る。
-- アーキテクチャを見るのはhome-managerだけを適用する時だけなので、
-- NixOSやTermuxでは未対応のアーキテクチャでも失敗にしない。
detectPlatform :: Probe -> Either UnsupportedArchitecture Platform
detectPlatform probe
  | probe.isNixos = Right (NixOS probe.hostName)
  | probe.isTermux = Right NixOnDroid
  | otherwise = HomeManager <$> parseArchitecture probe.machineName
