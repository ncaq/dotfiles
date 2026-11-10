-- | 購読するリポジトリの設定。
module GitRepoSubscribe.Repository
  ( Repository (..)
  ) where

import GitRepoSubscribe.PartialCloneFilter (PartialCloneFilter)
import GitRepoSubscribe.RemoteUrl (RemoteUrl)
import GitRepoSubscribe.WorktreePath (WorktreePath)
import Himari

-- | 検証済みの値だけから成る、Gitリポジトリの購読。
data Repository = Repository
  { remote :: RemoteUrl
  , worktree :: WorktreePath
  , partialCloneFilter :: PartialCloneFilter
  -- ^ 最初にcloneする時にだけ使う。
  }
  deriving stock (Eq, Show)
