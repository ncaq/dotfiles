-- | `nix build`へ渡すinstallable。
module NixGcRootHosts.Installable
  ( Installable (..)
  ) where

import Himari

newtype Installable = Installable Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)
