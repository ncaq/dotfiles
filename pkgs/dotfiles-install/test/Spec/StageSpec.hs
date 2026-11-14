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

-- | 実際のリポジトリの件名と同じく日本語を含み、JSONでエスケープが要る文字も含む件名。
japaneseSubject :: Text
japaneseSubject = "feat(test): 日本語の件名と\"引用符\"と\\バックスラッシュ"

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
    it "件名の日本語や引用符やバックスラッシュをそのまま伝える" do
      withRepository \repository -> do
        write repository "tracked" "changed\n"
        git repository ["commit", "--quiet", "-am", convert japaneseSubject]
        readLastCommit repository >>= (`shouldBe` LastCommit japaneseSubject False "master")
        stagedContent repository
          >>= ( `shouldBe`
                  Right
                    [aesonQQ|{
                      "subject": "feat(test): 日本語の件名と\"引用符\"と\\バックスラッシュ",
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
    it "注入の途中でGitが失敗したら、失敗を伝えて書いたファイルを残さない" do
      withRepository \repository -> do
        -- indexのロックを置いて、ファイルを書いた後の`git add`を失敗させる。
        write repository ".git/index.lock" ""
        result <- try (quietly (withStagedLastCommit repository (pure ())))
        result
          `shouldBe` Left @GitFailure @()
            (GitFailed ["add", "-f", "--", convert lastCommitFile] (ExitFailure 128))
        doesPathExist (repository </> lastCommitFile) >>= (`shouldBe` False)
    it "indexから外せなくても、処理の結果を返してファイルを消す" do
      withRepository \repository -> do
        -- 処理の中でindexのロックを置いて、後片付けの`git reset`を失敗させる。
        result <-
          quietly . withStagedLastCommit repository $
            "done" <$ write repository ".git/index.lock" ""
        result `shouldBe` ("done" :: Text)
        doesPathExist (repository </> lastCommitFile) >>= (`shouldBe` False)
    it "元からあった変更は後片付けで失わない" do
      withRepository \repository -> do
        write repository "tracked" "changed\n"
        git repository ["add", "tracked"]
        quietly (withStagedLastCommit repository (pure ()))
        gitText repository ["status", "--porcelain"] >>= (`shouldBe` "M  tracked")
