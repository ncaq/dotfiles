-- | 購読を処理した結果と、更新しなかった理由。
module GitRepoSubscribe.Outcome
  ( Outcome (..)
  , SkipReason (..)
  , skipWarning
  ) where

import GitRepoSubscribe.BranchName (BranchName, branchNameText)
import GitRepoSubscribe.ConfiguredRemote (ConfiguredRemote (..))
import GitRepoSubscribe.RemoteUrl (remoteUrlText)
import GitRepoSubscribe.Repository (Repository (..))
import GitRepoSubscribe.WorktreePath (worktreeFilePath)
import Himari

-- | 購読を処理した結果。
data Outcome
  = -- | worktreeが無かったのでcloneした。
    Cloned
  | -- | 既存のworktreeをfast-forwardした。既に最新だった場合も含む。
    Updated
  | -- | 安全に更新できないので何もしなかった。その理由。
    Skipped SkipReason
  deriving stock (Eq, Show)

-- | 安全に更新できない、失敗ではない理由。
data SkipReason
  = -- | 置き場所がシンボリックリンクである。
    SymbolicLink
  | -- | 置き場所はあるがGitのworktreeではない。
    NotWorktree
  | -- | 置き場所はworktreeの中だが、そのルートではない。
    NotWorktreeRoot
  | -- | `origin`が無い。
    NoOrigin
  | -- | `origin`のURLが設定と違う。その実際のURL。
    OriginMismatch ConfiguredRemote
  | -- | 追跡されているか未追跡の、ローカルの変更がある。
    LocalChanges
  | -- | `HEAD`がdetachedである。
    DetachedHead
  | -- | まだコミットが無い。
    UnbornHead
  | -- | リモートにデフォルトブランチを問い合わせられなかった。
    RemoteUnavailable
  | -- | リモートの応答からデフォルトブランチが分からなかった。
    DefaultBranchUnknown
  | -- | デフォルトブランチ以外をチェックアウトしている。今のブランチと、デフォルトブランチ。
    NotDefaultBranch BranchName BranchName
  | -- | デフォルトブランチのfetchが失敗した。
    FetchFailed
  | -- | fetchの間に`origin`のURLが変わった。
    OriginChanged
  | -- | fetchの間に`HEAD`が変わった。
    HeadChanged
  | -- | fetchの間にチェックアウトしているブランチが変わった。
    BranchChanged
  | -- | fetchの間にローカルの変更が増えた。
    LocalChangesDuringFetch
  | -- | fetchしたコミットへfast-forwardできなかった。
    FastForwardFailed
  deriving stock (Eq, Show)

-- | 更新しなかった理由を、人が読む警告にする。
skipWarning :: Repository -> SkipReason -> Text
skipWarning repository reason = message <> "; skipping update."
 where
  path = convert (worktreeFilePath repository.worktree)
  url = remoteUrlText repository.remote
  message = case reason of
    SymbolicLink -> path <> " is a symbolic link"
    NotWorktree -> path <> " is not a Git worktree"
    NotWorktreeRoot -> path <> " is not the root of its Git worktree"
    NoOrigin -> path <> " has no origin remote"
    OriginMismatch (ConfiguredRemote actual) ->
      "origin URL of " <> path <> " is " <> actual <> ", expected " <> url
    LocalChanges -> path <> " has local changes"
    DetachedHead -> path <> " has a detached HEAD"
    UnbornHead -> path <> " has an unborn HEAD"
    RemoteUnavailable -> "unable to query the default branch of " <> url
    DefaultBranchUnknown -> "unable to determine the default branch of " <> url
    NotDefaultBranch current defaultBranch ->
      path
        <> " is on "
        <> branchNameText current
        <> ", not the default branch "
        <> branchNameText defaultBranch
    FetchFailed -> "unable to fetch " <> url
    OriginChanged -> "origin URL of " <> path <> " changed while fetching"
    HeadChanged -> "HEAD of " <> path <> " changed while fetching"
    BranchChanged -> "branch of " <> path <> " changed while fetching"
    LocalChangesDuringFetch -> path <> " gained local changes while fetching"
    FastForwardFailed -> "unable to fast-forward " <> path
