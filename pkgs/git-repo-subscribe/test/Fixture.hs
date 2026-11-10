-- | テストで使う、一時ディレクトリの中のリモートと作業用のリポジトリ。
--
-- リモートには2つのコミットを置く。
-- 最初のコミットにだけあるblobを`historicalBlob`として覚えておき、
-- partial cloneがそれを取ってきていないことを確かめられるようにする。
module Fixture
  ( Fixture (..)
  , withFixture
  , repository
  , repositoryAt
  , pushUpdate
  , commitLocally
  , git
  , gitIn
  , gitTextIn
  , gitSucceedsOutside
  , temporaryRefs
  , historicalBlobFetched
  ) where

import Data.ByteString qualified as B
import Data.Text (strip)
import GitRepoSubscribe.Git.Environment (gitEnvironment)
import GitRepoSubscribe.PartialCloneFilter (parsePartialCloneFilter)
import GitRepoSubscribe.RemoteUrl (RemoteUrl, parseRemoteUrl)
import GitRepoSubscribe.Repository (Repository (..))
import GitRepoSubscribe.WorktreePath (parseWorktreePath)
import Himari
import System.Process.Typed qualified

data Fixture = Fixture
  { root :: FilePath
  -- ^ 一時ディレクトリ。
  , remote :: FilePath
  -- ^ bareなリモート。
  , remoteUrl :: RemoteUrl
  , source :: FilePath
  -- ^ リモートへpushするための作業用のリポジトリ。
  , subscription :: FilePath
  -- ^ 購読の置き場所。最初は無い。
  , hooks :: FilePath
  -- ^ 開発環境のフックを走らせないための空のディレクトリ。
  , historicalBlob :: Text
  }

-- | リモートを用意して渡し、終わったら一時ディレクトリごと消す。
withFixture :: (MonadThrow m, MonadUnliftIO m) => (Fixture -> m a) -> m a
withFixture action = withSystemTempDirectory "git-repo-subscribe" \root -> do
  let remote = root </> "remote.git"
      source = root </> "source"
      subscription = root </> "subscription"
      hooks = root </> "hooks"
  remoteUrl <- either throwM pure (parseRemoteUrl (convert ("file://" <> remote)))
  git ["init", "--bare", "--initial-branch=master", remote]
  gitIn remote ["config", "uploadpack.allowFilter", "true"]
  git ["init", "--initial-branch=master", source]
  createDirectory hooks
  identify hooks source
  gitIn source ["remote", "add", "origin", remote]
  liftIO (B.writeFile (source </> "historical") "historical\n")
  historicalBlob <- gitTextIn source ["hash-object", "historical"]
  gitIn source ["add", "historical"]
  gitIn source ["commit", "-m", "historical"]
  removeFile (source </> "historical")
  liftIO (B.writeFile (source </> "tracked") "initial\n")
  gitIn source ["add", "--all"]
  gitIn source ["commit", "-m", "initial"]
  gitIn source ["push", "-u", "origin", "master"]
  action Fixture{..}

-- | コミットできるように、作者とフックの場所をそのリポジトリにだけ設定する。
identify :: (MonadIO m) => FilePath -> FilePath -> m ()
identify hooks path = do
  gitIn path ["config", "core.hooksPath", hooks]
  gitIn path ["config", "user.email", "test@example.com"]
  gitIn path ["config", "user.name", "Test"]

-- | フィクスチャの置き場所への購読。
repository :: (MonadThrow m) => Fixture -> m Repository
repository fixture = repositoryAt fixture fixture.subscription

-- | フィクスチャのリモートを、指定の置き場所で購読する。
repositoryAt :: (MonadThrow m) => Fixture -> FilePath -> m Repository
repositoryAt fixture path =
  either throwM pure $
    Repository fixture.remoteUrl
      <$> over _Left toException (parseWorktreePath path)
      <*> over _Left toException (parsePartialCloneFilter "blob:none")

-- | 追跡されているファイルを書き換えてリモートへpushする。
pushUpdate :: (MonadIO m) => Fixture -> ByteString -> String -> m ()
pushUpdate fixture content message = do
  liftIO (B.writeFile (fixture.source </> "tracked") content)
  gitIn fixture.source ["commit", "-am", message]
  gitIn fixture.source ["push"]

-- | 購読の置き場所で追跡されているファイルを書き換えてコミットし、そのコミットのIDを返す。
--
-- リモートと分岐した状態を作るのに使う。
commitLocally :: (MonadIO m) => Fixture -> m Text
commitLocally fixture = do
  identify fixture.hooks fixture.subscription
  liftIO (B.writeFile (fixture.subscription </> "tracked") "local\n")
  gitIn fixture.subscription ["commit", "-am", "local"]
  gitTextIn fixture.subscription ["rev-parse", "HEAD"]

-- | 開発環境のグローバルとシステムの設定から切り離してGitを起動する設定。
isolated :: (MonadIO m) => [(String, String)] -> [String] -> m (ProcessConfig () () ())
isolated extra args = do
  inherited <- getEnvironment
  -- 本体と同じ環境変数にする。
  -- 設定を切り離すだけだと、Gitのフックの中からテストを走らせた時に、
  -- 継いだ`GIT_DIR`などがフィクスチャの操作を呼び出し元のリポジトリへ向けてしまう。
  pure (System.Process.Typed.setEnv (extra <> gitEnvironment inherited) (proc "git" args))

-- | Gitを実行する。失敗したら出力を付けた例外になる。
git :: (MonadIO m) => [String] -> m ()
git = isolated [] >=> void . readProcess_

-- | 指定のリポジトリでGitを実行する。
gitIn :: (MonadIO m) => FilePath -> [String] -> m ()
gitIn path args = git (["-C", path] <> args)

-- | 指定のリポジトリでGitを実行して、前後の空白を除いた標準出力を返す。
gitTextIn :: (MonadIO m) => FilePath -> [String] -> m Text
gitTextIn path args =
  strip . convert <$> (isolated [] (["-C", path] <> args) >>= readProcessStdout_)

-- | どのリポジトリにも属さない一時ディレクトリでGitを実行して、成功したかを返す。
--
-- Git本体の判定を、作業中のリポジトリの状態に左右されずに聞くのに使う。
gitSucceedsOutside :: (MonadUnliftIO m) => [String] -> m Bool
gitSucceedsOutside args = withSystemTempDirectory "git-repo-subscribe" \dir -> do
  config <- isolated [] args
  (== ExitSuccess)
    <$> runProcess (setWorkingDir dir (setStdout nullStream (setStderr nullStream config)))

-- | 残っているfetch用の一時ref。改行区切り。
temporaryRefs :: (MonadIO m) => FilePath -> m Text
temporaryRefs path =
  gitTextIn path ["for-each-ref", "--format=%(refname)", "refs/git-repo-subscribe"]

-- | 過去のコミットにだけあるblobが、購読の置き場所に取ってこられているか。
--
-- 無いblobをその場で取りに行かせないようにして調べる。
historicalBlobFetched :: (MonadIO m) => Fixture -> m Bool
historicalBlobFetched fixture = do
  config <-
    isolated
      [("GIT_NO_LAZY_FETCH", "1")]
      ["-C", fixture.subscription, "cat-file", "-e", convert fixture.historicalBlob]
  (== ExitSuccess) <$> runProcess (setStderr nullStream config)
