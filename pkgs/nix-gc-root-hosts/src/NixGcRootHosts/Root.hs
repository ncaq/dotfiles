-- | GC rootとして保持する閉包。
module NixGcRootHosts.Root
  ( Root (..)
  , nixosRoot
  , homeRoot
  ) where

import Himari
import NixGcRootHosts.Flake (Flake (..))
import NixGcRootHosts.Installable (Installable (..))
import NixGcRootHosts.RootName (RootName (..))

data Root = Root
  { name :: RootName
  , installable :: Installable
  }
  deriving stock (Eq, Show)

-- | `nixosConfigurations`のホストのtoplevel。
nixosRoot :: Flake -> Text -> Root
nixosRoot (Flake flake) host =
  Root
    { name = RootName ("nixos-" <> host)
    , installable =
        Installable (flake <> "#nixosConfigurations." <> host <> ".config.system.build.toplevel")
    }

-- | `homeConfigurations`のシステムのhome-managerの閉包。
homeRoot :: Flake -> Text -> Root
homeRoot (Flake flake) system =
  Root
    { name = RootName ("home-manager-" <> system)
    , installable = Installable (flake <> "#homeConfigurations." <> system <> ".activationPackage")
    }
