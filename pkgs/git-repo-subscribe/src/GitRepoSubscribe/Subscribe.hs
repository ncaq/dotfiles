-- | 購読の本体。無ければcloneし、あれば安全な時だけfast-forwardする。
--
-- 既存のworktreeを更新するのは、以下が全て揃った時だけである。
--
-- * 設定と同じ`origin`を向いている
-- * ローカルの変更が無い
-- * リモートのデフォルトブランチをチェックアウトしている
--
-- 揃わない時は何も変えずに、理由を`Skipped`で返す。
-- 想定のうちなので失敗にはしない。
module GitRepoSubscribe.Subscribe
  ( subscribe
  ) where

import Control.Monad.Except (ExceptT (..), runExceptT, throwError)
import GitRepoSubscribe.BranchName (branchNameText)
import GitRepoSubscribe.ConfiguredRemote (configuredAs)
import GitRepoSubscribe.DefaultBranch (parseDefaultBranch, queryDefaultBranch)
import GitRepoSubscribe.Git
  ( ErrorOutput (..)
  , gitChecked
  , gitOptionalText
  , gitRun
  , gitText
  , inWorktree
  )
import GitRepoSubscribe.Outcome (Outcome (..), SkipReason (..))
import GitRepoSubscribe.PartialCloneFilter (filterArgument)
import GitRepoSubscribe.RemoteUrl (remoteUrlText)
import GitRepoSubscribe.Repository (Repository (..))
import GitRepoSubscribe.Worktree
import GitRepoSubscribe.WorktreePath (worktreeFilePath)
import Himari
import System.IO.Error (isDoesNotExistError)
import System.Process (getCurrentPid)

-- | 無いリポジトリをcloneするか、既存のworktreeを安全に更新する。
--
-- 安全でない状態は`Skipped`で返す。
-- Gitの実行やその出力が続けられない形で壊れている時は`GitFailure`などの例外を投げる。
subscribe :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => Repository -> m Outcome
subscribe repository =
  -- リンク切れのシンボリックリンクも「ある」と見なすために、リンクを辿らずに調べる。
  -- 辿ると無いように見えて、リンクの先へcloneしてしまう。
  tryJust (guard . isDoesNotExistError) (pathIsSymbolicLink path) >>= \case
    Left () -> Cloned <$ clone repository
    Right True -> pure (Skipped SymbolicLink)
    Right False -> either Skipped (const Updated) <$> runExceptT (update repository)
 where
  path = worktreeFilePath repository.worktree

-- | 完全なコミット履歴を保ったまま、過去のblobを後回しにしてcloneする。
clone :: (MonadIO m, MonadThrow m) => Repository -> m ()
clone repository = do
  createDirectoryIfMissing True (takeDirectory path)
  gitChecked
    [ "clone"
    , convert (filterArgument repository.partialCloneFilter)
    , "--single-branch"
    , "--"
    , convert (remoteUrlText repository.remote)
    , path
    ]
 where
  path = worktreeFilePath repository.worktree

-- | 既存のworktreeを調べて、安全ならfast-forwardする。
--
-- 安全でないと分かった時点で、その理由で打ち切る。
update
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => Repository -> ExceptT SkipReason m ()
update repository = do
  insideWorktree <-
    gitOptionalText Discarded (inWorktree path ["rev-parse", "--is-inside-work-tree"])
  skipUnless NotWorktree (insideWorktree == Just "true")
  toplevel <- gitText (inWorktree path ["rev-parse", "--show-toplevel"])
  isToplevel <- (==) <$> canonicalizePath path <*> canonicalizePath (convert toplevel)
  skipUnless NotWorktreeRoot isToplevel
  origin <- originUrl path >>= orSkip NoOrigin
  skipUnless (OriginMismatch origin) (configuredAs repository.remote origin)
  branch <- currentBranch path >>= orSkip DetachedHead
  -- 未追跡のファイルまで調べるので大きなworktreeでは高くつく。
  -- originやbranchで弾ける時はここまで来ない。
  hasLocalChanges path >>= skipUnless LocalChanges . not
  remoteHead <- queryDefaultBranch repository.remote >>= orSkip RemoteUnavailable
  defaultBranch <-
    either throwM pure (parseDefaultBranch remoteHead) >>= orSkip DefaultBranchUnknown
  skipUnless (NotDefaultBranch branch defaultBranch) (branch == defaultBranch)
  headId <- optionalHeadId path >>= orSkip UnbornHead
  -- 並行して走る他の購読とぶつからないように、プロセスごとの一時refへfetchする。
  processId <- liftIO getCurrentPid
  let fetchRef = "refs/git-repo-subscribe/" <> show (toInteger processId)
      heads = "+refs/heads/" <> convert (branchNameText branch)
      -- 同名のタグを拾わないように、fetch元は`refs/heads`まで書く。
      -- 追跡refも同じfetchで進めて、後の`git status`が古い位置を見ないようにする。
      refspecs =
        [ heads <> ":" <> fetchRef
        , heads <> ":refs/remotes/origin/" <> convert (branchNameText branch)
        ]
      initial = WorktreeState{origin = Just origin, headId = Just headId, branch = Just branch}
  ExceptT $
    runExceptT (fastForward initial fetchRef refspecs) `finally` removeTemporaryRef path fetchRef
 where
  path = worktreeFilePath repository.worktree
  fastForward initial fetchRef refspecs = do
    gitRun (inWorktree path (["fetch", "--no-write-fetch-head", "origin"] <> refspecs))
      >>= skipUnless FetchFailed . (== ExitSuccess)
    -- fetchの間に人や他のプロセスがworktreeを触っていたら、mergeで壊しかねないのでやめる。
    current <- readWorktreeState path
    detectConcurrentChange initial current (hasLocalChanges path) >>= traverse_ throwError
    -- ignoreされたファイルも上書きさせない。
    gitRun (inWorktree path ["merge", "--ff-only", "--no-overwrite-ignore", fetchRef])
      >>= skipUnless FastForwardFailed . (== ExitSuccess)

-- | 安全でなければ、その理由で打ち切る。
skipUnless :: (Monad m) => SkipReason -> Bool -> ExceptT SkipReason m ()
skipUnless reason safe = unless safe (throwError reason)

-- | 値が無ければ、その理由で打ち切る。
orSkip :: (Monad m) => SkipReason -> Maybe a -> ExceptT SkipReason m a
orSkip reason = maybe (throwError reason) pure

-- | fetchに使った一時refを消す。
--
-- 消せなくても更新の結果には関わらないので、記録だけして続ける。
removeTemporaryRef :: (MonadIO m, MonadLogger m) => FilePath -> String -> m ()
removeTemporaryRef path fetchRef = do
  code <- gitRun (inWorktree path ["update-ref", "-d", fetchRef])
  unless (code == ExitSuccess) . logWarnN . convert $
    "unable to remove temporary ref " <> fetchRef <> ": git exited with " <> show code
