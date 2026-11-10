-- | 購読の置き場所。
module GitRepoSubscribe.WorktreePath
  ( WorktreePath
  , parseWorktreePath
  , worktreeFilePath
  ) where

import GitRepoSubscribe.Failure (WorktreePathError (..))
import Himari

-- | worktreeの置き場所にできる、正規化された絶対パス。
--
-- 構築子は公開せず、検証を通った値しか作れないようにする。
newtype WorktreePath = WorktreePath FilePath
  deriving stock (Eq, Show)

-- | 検証済みのファイルシステムのパス。
worktreeFilePath :: WorktreePath -> FilePath
worktreeFilePath (WorktreePath path) = path

-- | worktreeのパスを検証する。
parseWorktreePath :: FilePath -> Either WorktreePathError WorktreePath
parseWorktreePath path
  | not (isAbsolute path) = Left RelativePath
  -- `//`や`/.`のような別の綴りもルートなので、正規化してから比べる。
  | normalise path == "/" = Left RootPath
  | ".." `elem` splitDirectories path = Left NotNormalizedPath
  | otherwise = Right (WorktreePath path)
