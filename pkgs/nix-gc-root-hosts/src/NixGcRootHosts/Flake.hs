-- | 構成を列挙するflake。
module NixGcRootHosts.Flake
  ( Flake (..)
  , deployedFlake
  ) where

import Himari

-- | flakeの参照。パスでもURLでも良い。
newtype Flake = Flake Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | デプロイ時に配置されるflake。
--
-- 作業ツリーではなくこれを参照するので、
-- 登録されるのは今動いている構成と同じリビジョンの閉包になる。
deployedFlake :: Flake
deployedFlake = "/etc/nixos-flake"
