-- | 購読の本体のテスト。
--
-- 一時ディレクトリの中の実際のGitリポジトリで、
-- 更新する条件と、更新せずに守る条件を確かめる。
module Spec.SubscribeSpec (tests) where

import Data.ByteString qualified as B
import Fixture
import GitRepoSubscribe.BranchName (parseBranchName)
import GitRepoSubscribe.ConfiguredRemote (ConfiguredRemote (..))
import GitRepoSubscribe.Failure (GitFailure (..))
import GitRepoSubscribe.Outcome (Outcome (..), SkipReason (..))
import GitRepoSubscribe.RemoteUrl (parseRemoteUrl, remoteUrlText)
import GitRepoSubscribe.Repository (Repository)
import GitRepoSubscribe.Subscribe
import Himari
import Test.Sandwich

-- | cloneを済ませた状態から始める。
withSubscription :: (Fixture -> Repository -> ExampleT context IO a) -> ExampleT context IO a
withSubscription action = withFixture \fixture -> do
  target <- repository fixture
  subscribe target >>= (`shouldBe` Cloned)
  action fixture target

tests :: TopSpec
tests = describe "subscribe" do
  it "完全な履歴を保ったままpartial cloneする" do
    withSubscription \fixture _ -> do
      gitTextIn fixture.subscription ["rev-list", "--count", "HEAD"] >>= (`shouldBe` "2")
      gitTextIn fixture.subscription ["config", "--get", "remote.origin.partialclonefilter"]
        >>= (`shouldBe` "blob:none")
      gitTextIn fixture.subscription ["config", "--get", "remote.origin.promisor"]
        >>= (`shouldBe` "true")
      gitTextIn fixture.subscription ["rev-parse", "--is-shallow-repository"]
        >>= (`shouldBe` "false")
      historicalBlobFetched fixture >>= (`shouldBe` False)
  it "cleanなデフォルトブランチをfast-forwardする" do
    withSubscription \fixture target -> do
      pushUpdate fixture "updated\n" "update"
      subscribe target >>= (`shouldBe` Updated)
      sourceHead <- gitTextIn fixture.source ["rev-parse", "HEAD"]
      gitTextIn fixture.subscription ["rev-parse", "HEAD"] >>= (`shouldBe` sourceHead)
      gitTextIn fixture.subscription ["rev-parse", "origin/master"] >>= (`shouldBe` sourceHead)
      temporaryRefs fixture.subscription >>= (`shouldBe` "")
      historicalBlobFetched fixture >>= (`shouldBe` False)
  it "同名のタグがあってもデフォルトブランチをfetchする" do
    withSubscription \fixture target -> do
      gitIn fixture.source ["tag", "master", "HEAD~1"]
      gitIn fixture.source ["push", "origin", "refs/tags/master"]
      pushUpdate fixture "updated\n" "update"
      subscribe target >>= (`shouldBe` Updated)
      sourceHead <- gitTextIn fixture.source ["rev-parse", "refs/heads/master"]
      gitTextIn fixture.subscription ["rev-parse", "HEAD"] >>= (`shouldBe` sourceHead)
  it "リモートが変わっていなければ繰り返しても何も変えない" do
    withSubscription \fixture target -> do
      initialHead <- gitTextIn fixture.subscription ["rev-parse", "HEAD"]
      subscribe target >>= (`shouldBe` Updated)
      gitTextIn fixture.subscription ["rev-parse", "HEAD"] >>= (`shouldBe` initialHead)
      temporaryRefs fixture.subscription >>= (`shouldBe` "")
  it "分岐したデフォルトブランチはHEADを変えずに飛ばす" do
    withSubscription \fixture target -> do
      localHead <- commitLocally fixture
      pushUpdate fixture "remote\n" "remote"
      subscribe target >>= (`shouldBe` Skipped FastForwardFailed)
      gitTextIn fixture.subscription ["rev-parse", "HEAD"] >>= (`shouldBe` localHead)
      temporaryRefs fixture.subscription >>= (`shouldBe` "")
  it "デフォルトブランチ以外にいる時は飛ばす" do
    withSubscription \fixture target -> do
      gitIn fixture.subscription ["switch", "-c", "topic"]
      pushUpdate fixture "branch update\n" "branch-update"
      topic <- either throwM pure (parseBranchName "topic")
      master <- either throwM pure (parseBranchName "master")
      subscribe target >>= (`shouldBe` Skipped (NotDefaultBranch topic master))
  it "未追跡のファイルがあれば飛ばす" do
    withSubscription \fixture target -> do
      liftIO (B.writeFile (fixture.subscription </> "untracked") "dirty\n")
      subscribe target >>= (`shouldBe` Skipped LocalChanges)
  it "追跡されているファイルが変更されていれば飛ばす" do
    withSubscription \fixture target -> do
      liftIO (B.writeFile (fixture.subscription </> "tracked") "modified\n")
      subscribe target >>= (`shouldBe` Skipped LocalChanges)
  it "ステージされた変更があれば飛ばす" do
    withSubscription \fixture target -> do
      liftIO (B.writeFile (fixture.subscription </> "staged") "staged\n")
      gitIn fixture.subscription ["add", "staged"]
      subscribe target >>= (`shouldBe` Skipped LocalChanges)
  it "追跡されているファイルが消されていれば飛ばす" do
    withSubscription \fixture target -> do
      removeFile (fixture.subscription </> "tracked")
      subscribe target >>= (`shouldBe` Skipped LocalChanges)
  it "detachedなHEADは飛ばす" do
    withSubscription \fixture target -> do
      gitIn fixture.subscription ["switch", "--detach"]
      subscribe target >>= (`shouldBe` Skipped DetachedHead)
  it "リポジトリではないディレクトリは中身を変えずに飛ばす" do
    withFixture \fixture -> do
      let directory = fixture.root </> "not-a-repository"
      createDirectory directory
      target <- repositoryAt fixture directory
      subscribe target >>= (`shouldBe` Skipped NotWorktree)
      listDirectory directory >>= (`shouldBe` [])
  it "worktreeの中のディレクトリは中身を変えずに飛ばす" do
    withSubscription \fixture _ -> do
      let nested = fixture.subscription </> "nested"
      createDirectory nested
      target <- repositoryAt fixture nested
      subscribe target >>= (`shouldBe` Skipped NotWorktreeRoot)
      listDirectory nested >>= (`shouldBe` [])
  it "`.git`ディレクトリは飛ばす" do
    withSubscription \fixture _ -> do
      target <- repositoryAt fixture (fixture.subscription </> ".git")
      subscribe target >>= (`shouldBe` Skipped NotWorktree)
  it "リンク切れのシンボリックリンクの先へcloneしない" do
    withFixture \fixture -> do
      let destination = fixture.root </> "destination"
      createFileLink destination fixture.subscription
      target <- repository fixture
      subscribe target >>= (`shouldBe` Skipped SymbolicLink)
      doesPathExist destination >>= (`shouldBe` False)
  it "ignoreされたファイルを上書きしない" do
    withSubscription \fixture target -> do
      liftIO (B.writeFile (fixture.subscription </> ".git/info/exclude") "ignored\n")
      liftIO (B.writeFile (fixture.subscription </> "ignored") "local ignored content\n")
      liftIO (B.writeFile (fixture.source </> "ignored") "remote content\n")
      gitIn fixture.source ["add", "ignored"]
      gitIn fixture.source ["commit", "-m", "ignored"]
      gitIn fixture.source ["push"]
      subscribe target >>= (`shouldBe` Skipped FastForwardFailed)
      liftIO (B.readFile (fixture.subscription </> "ignored"))
        >>= (`shouldBe` "local ignored content\n")
      temporaryRefs fixture.subscription >>= (`shouldBe` "")
  it "originが設定と違えば実際のURLを報告して飛ばす" do
    withSubscription \fixture target -> do
      let other = fixture.root </> "other.git"
          otherUrl = "file://" <> other
      git ["clone", "--bare", fixture.remote, other]
      gitIn fixture.subscription ["remote", "set-url", "origin", otherUrl]
      subscribe target
        >>= (`shouldBe` Skipped (OriginMismatch (ConfiguredRemote (convert otherUrl))))
  it "originが無ければHEADを変えずに飛ばす" do
    withSubscription \fixture target -> do
      gitIn fixture.subscription ["remote", "remove", "origin"]
      initialHead <- gitTextIn fixture.subscription ["rev-parse", "HEAD"]
      subscribe target >>= (`shouldBe` Skipped NoOrigin)
      gitTextIn fixture.subscription ["rev-parse", "HEAD"] >>= (`shouldBe` initialHead)
  it "リモートに届かなければ飛ばす" do
    withSubscription \fixture target -> do
      removeDirectoryRecursive fixture.remote
      subscribe target >>= (`shouldBe` Skipped RemoteUnavailable)
  it "fetchが失敗したら一時refを残さずに飛ばす" do
    withSubscription \fixture target -> do
      initialHead <- gitTextIn fixture.subscription ["rev-parse", "HEAD"]
      gitIn fixture.subscription ["config", "remote.origin.uploadpack", "false"]
      subscribe target >>= (`shouldBe` Skipped FetchFailed)
      gitTextIn fixture.subscription ["rev-parse", "HEAD"] >>= (`shouldBe` initialHead)
      temporaryRefs fixture.subscription >>= (`shouldBe` "")
  it "リモートにデフォルトブランチが無ければ飛ばす" do
    withSubscription \fixture target -> do
      gitIn fixture.remote ["symbolic-ref", "HEAD", "refs/heads/missing"]
      subscribe target >>= (`shouldBe` Skipped DefaultBranchUnknown)
  it "まだコミットが無いリポジトリは飛ばす" do
    withFixture \fixture -> do
      let unborn = fixture.root </> "unborn"
      git ["init", "--initial-branch=master", unborn]
      gitIn unborn ["remote", "add", "origin", convert (remoteUrlText fixture.remoteUrl)]
      target <- repositoryAt fixture unborn
      subscribe target >>= (`shouldBe` Skipped UnbornHead)
  it "cloneの失敗をGitの終了コードと共に例外にして、置き場所を作らない" do
    withFixture \fixture -> do
      let destination = fixture.root </> "failed-subscription"
      missing <-
        either throwM pure (parseRemoteUrl (convert ("file://" <> fixture.root </> "missing.git")))
      target <- repositoryAt fixture{remoteUrl = missing} destination
      -- `git clone`は届かないリモートに128で終わる。引数は置き場所ごとに変わるので見ない。
      try (subscribe target) >>= \case
        Left (GitFailed _ code) -> code `shouldBe` ExitFailure 128
        other -> expectationFailure ("cloneがGitの失敗として報告されませんでした: " <> show other)
      doesPathExist destination >>= (`shouldBe` False)
