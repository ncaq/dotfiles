-- | 最新のコミットの情報の注入と、後片付けのテスト。
module Spec.StageSpec (tests) where

import DotfilesInstall.Failure (GitFailure (..))
import DotfilesInstall.LastCommit (LastCommit (..))
import DotfilesInstall.LastCommit.Stage
import Fixture
import Himari
import Test.Sandwich

-- | 注入している間に読める、注入されたファイルの中身。
stagedContent :: (MonadIO m) => FilePath -> m (Either String Value)
stagedContent repository =
  quietly . withStagedLastCommit repository . liftIO $
    eitherDecodeFileStrict (repository </> lastCommitFile)

tests :: TopSpec
tests = do
  describe "readLastCommit" do
    it "変更が無い時はdirtyにしない" do
      withRepository $
        readLastCommit >=> (`shouldBe` LastCommit "feat(test): initial" False "master")
    it "追跡しているファイルを書き換えていたらdirtyにする" do
      withRepository \repository -> do
        write repository "tracked" "changed\n"
        readLastCommit repository
          >>= (`shouldBe` LastCommit "feat(test): initial" True "master")
    it "stagingしただけの変更もdirtyにする" do
      withRepository \repository -> do
        write repository "tracked" "changed\n"
        git repository ["add", "tracked"]
        readLastCommit repository
          >>= (`shouldBe` LastCommit "feat(test): initial" True "master")
    it "追跡していないファイルがあるだけならdirtyにしない" do
      withRepository \repository -> do
        write repository "untracked" "untracked\n"
        readLastCommit repository
          >>= (`shouldBe` LastCommit "feat(test): initial" False "master")
    it "今のブランチの名前を入れる" do
      withRepository \repository -> do
        git repository ["switch", "--quiet", "-c", "feature/branch"]
        readLastCommit repository
          >>= (`shouldBe` LastCommit "feat(test): initial" False "feature/branch")
    it "変更の有無を調べるGitが失敗したら、dirtyにせず失敗を伝える" do
      withRepository \repository -> do
        write repository ".git/index" "broken"
        result <- try (readLastCommit repository)
        result
          `shouldBe` Left @GitFailure @LastCommit (GitFailed ["diff", "--quiet"] (ExitFailure 128))
  describe "withStagedLastCommit" do
    it "処理の間はファイルをstagingしている" do
      withRepository \repository -> do
        staged <-
          quietly . withStagedLastCommit repository $
            gitText repository ["diff", "--cached", "--name-only"]
        staged `shouldBe` convert lastCommitFile
    it "注入したファイルは注入する前の状態を伝える" do
      withRepository $
        stagedContent
          >=> ( `shouldBe`
                  Right
                    [aesonQQ|{
                      "subject": "feat(test): initial",
                      "dirty": false,
                      "branch": "master"
                    }|]
              )
    it "処理が終わったらindexとファイルを元に戻す" do
      withRepository \repository -> do
        quietly (withStagedLastCommit repository (pure ()))
        gitText repository ["status", "--porcelain"] >>= (`shouldBe` "")
        doesPathExist (repository </> lastCommitFile) >>= (`shouldBe` False)
    it "処理が例外で終わってもindexとファイルを元に戻す" do
      withRepository \repository -> do
        result <- try (quietly (withStagedLastCommit repository (throwM (ExitFailure 1))))
        result `shouldBe` Left @ExitCode @() (ExitFailure 1)
        gitText repository ["status", "--porcelain"] >>= (`shouldBe` "")
        doesPathExist (repository </> lastCommitFile) >>= (`shouldBe` False)
    it "元からあった変更は後片付けで失わない" do
      withRepository \repository -> do
        write repository "tracked" "changed\n"
        git repository ["add", "tracked"]
        quietly (withStagedLastCommit repository (pure ()))
        gitText repository ["status", "--porcelain"] >>= (`shouldBe` "M  tracked")
