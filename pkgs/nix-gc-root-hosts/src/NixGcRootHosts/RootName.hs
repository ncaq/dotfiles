-- | GC rootのout-linkの名前。状態ディレクトリの直下のファイル名になる。
module NixGcRootHosts.RootName
  ( RootName (..)
  ) where

import Himari

newtype RootName = RootName Text
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)
