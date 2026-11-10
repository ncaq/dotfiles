-- | 既存のworktreeの状態の読み取りと、fetchの前後での比較。
module GitRepoSubscribe.Worktree
  ( WorktreeState (..)
  , readWorktreeState
  , detectConcurrentChange
  , hasLocalChanges
  , currentBranch
  , originUrl
  , optionalHeadId
  ) where

import Data.Text (stripPrefix)
import GitRepoSubscribe.BranchName (BranchName, parseBranchName)
import GitRepoSubscribe.CommitId (CommitId, parseCommitId)
import GitRepoSubscribe.ConfiguredRemote (ConfiguredRemote (..))
import GitRepoSubscribe.Git (ErrorOutput (..), gitOptionalText, gitText, inWorktree)
import GitRepoSubscribe.Outcome (SkipReason (..))
import Himari

-- | fetchの前後で変わっていないことを確かめる、worktreeの状態。
data WorktreeState = WorktreeState
  { origin :: Maybe ConfiguredRemote
  , headId :: CommitId
  , branch :: Maybe BranchName
  }
  deriving stock (Eq, Show)

-- | 今のworktreeの状態を読む。
readWorktreeState :: (MonadIO m, MonadThrow m) => FilePath -> m WorktreeState
readWorktreeState path =
  WorktreeState
    <$> originUrl path
    <*> (gitText (inWorktree path ["rev-parse", "HEAD"]) >>= either throwM pure . parseCommitId)
    <*> currentBranch path

-- | fetchの前後の状態を比べて、間に変わったものがあればその理由を返す。
--
-- ローカルの変更を調べるのは高くつくので、他が変わっていない時にだけ実行する。
detectConcurrentChange
  :: (Monad m) => WorktreeState -> WorktreeState -> m Bool -> m (Maybe SkipReason)
detectConcurrentChange initial current hasChanges
  | current.origin /= initial.origin = pure (Just OriginChanged)
  | current.headId /= initial.headId = pure (Just HeadChanged)
  | current.branch /= initial.branch = pure (Just BranchChanged)
  | otherwise = bool Nothing (Just LocalChangesDuringFetch) <$> hasChanges

-- | 追跡されているファイルの変更か、未追跡のファイルがあるか。
hasLocalChanges :: (MonadIO m, MonadThrow m) => FilePath -> m Bool
hasLocalChanges path =
  (/= mempty)
    <$> gitText
      ( inWorktree
          path
          ["-c", "core.untrackedCache=true", "status", "--porcelain=v1", "--untracked-files=normal"]
      )

-- | チェックアウトしているブランチ。detachedなら`Nothing`。
currentBranch :: (MonadIO m, MonadThrow m) => FilePath -> m (Maybe BranchName)
currentBranch path =
  gitOptionalText Inherited (inWorktree path ["symbolic-ref", "--quiet", "HEAD"])
    >>= traverse (either throwM pure . parseBranchName . dropHeads)
 where
  dropHeads name = fromMaybe name (stripPrefix "refs/heads/" name)

-- | `origin`のURL。`origin`が無ければ`Nothing`。
originUrl :: (MonadIO m, MonadThrow m) => FilePath -> m (Maybe ConfiguredRemote)
originUrl path =
  fmap ConfiguredRemote
    <$> gitOptionalText Inherited (inWorktree path ["remote", "get-url", "origin"])

-- | `HEAD`のコミット。まだコミットが無ければ`Nothing`。
optionalHeadId :: (MonadIO m, MonadThrow m) => FilePath -> m (Maybe CommitId)
optionalHeadId path =
  gitOptionalText Inherited (inWorktree path ["rev-parse", "--verify", "HEAD"])
    >>= traverse (either throwM pure . parseCommitId)
