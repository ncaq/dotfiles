-- | 状態ディレクトリから消すものの決定。
module NixGcRootHosts.Stale
  ( staleEntries
  ) where

import Himari
import NixGcRootHosts.RootName (RootName (..))

-- | 状態ディレクトリの中身のうち、今の構成に対応しないものを返す。
--
-- flakeから消えた構成のrootを消して、
-- 不要になった閉包をいつまでも保持し続けないようにする。
staleEntries
  :: [RootName]
  -- ^ 今の構成のrootの名前。
  -> [FilePath]
  -- ^ 状態ディレクトリの直下にある名前。
  -> [FilePath]
staleEntries roots = filter (`notElem` kept)
 where
  kept = [convert name | RootName name <- roots]
