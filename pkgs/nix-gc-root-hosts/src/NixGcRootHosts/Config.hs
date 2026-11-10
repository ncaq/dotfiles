-- | 起動時に受け取る設定。環境変数から受け取る。
--
-- * `STATE_DIRECTORY`: GC rootのout-linkを置くディレクトリ。systemdの`StateDirectory`が設定する。
-- * `NIX_GC_ROOT_HOSTS_FLAKE`: 構成を列挙するflake。無ければデプロイ時に配置されるflakeを使う。
module NixGcRootHosts.Config
  ( Config (..)
  , configFrom
  ) where

import Himari
import NixGcRootHosts.Failure (ConfigFailure (..))
import NixGcRootHosts.Flake (Flake (..), deployedFlake)

data Config = Config
  { stateDirectory :: FilePath
  , flake :: Flake
  }
  deriving stock (Eq, Show)

-- | 環境変数を引く関数から設定を組み立てる。空は無いのと同じに扱う。
configFrom :: (Text -> Maybe Text) -> Either ConfigFailure Config
configFrom lookupVariable =
  Config
    <$> maybe (Left (MissingVariable stateVariable)) (Right . convert) (present stateVariable)
    <*> pure (maybe deployedFlake Flake (present "NIX_GC_ROOT_HOSTS_FLAKE"))
 where
  stateVariable = "STATE_DIRECTORY"
  present = mfilter (/= mempty) . lookupVariable
