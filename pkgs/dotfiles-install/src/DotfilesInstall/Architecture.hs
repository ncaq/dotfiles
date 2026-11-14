-- | home-managerの構成を用意しているアーキテクチャ。
module DotfilesInstall.Architecture
  ( Architecture (..)
  , parseArchitecture
  , architectureSystem
  ) where

import DotfilesInstall.Failure (UnsupportedArchitecture (..))
import Himari

data Architecture
  = X86_64
  | Aarch64
  deriving stock (Bounded, Enum, Eq, Show)

-- | `uname`の`machine`の値から決める。
parseArchitecture :: String -> Either UnsupportedArchitecture Architecture
parseArchitecture = \case
  "x86_64" -> Right X86_64
  "aarch64" -> Right Aarch64
  machine -> Left (UnsupportedArchitecture machine)

-- | Nixのsystemの名前。`homeConfigurations`の属性名にしている。
architectureSystem :: Architecture -> String
architectureSystem = \case
  X86_64 -> "x86_64-linux"
  Aarch64 -> "aarch64-linux"
