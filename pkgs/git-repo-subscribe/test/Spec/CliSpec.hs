-- | コマンドライン引数からの実行と、終了の仕方のテスト。
module Spec.CliSpec (tests) where

import Data.Text (isInfixOf)
import Fixture
import GitRepoSubscribe.Cli (run)
import GitRepoSubscribe.RemoteUrl (remoteUrlText)
import Himari
import Test.Sandwich

-- | ログを端末へ出さずに集めて、結果と共に返す。
--
-- `ExitCode`の例外で終わった時も、それまでのログを見られるように結果は`Either`で返す。
runCapturing :: (MonadIO m) => Himari SimpleEnv a -> m (Either ExitCode a, [Text])
runCapturing action = do
  logs <- newIORef []
  result <-
    runSimpleEnvWith
      (\_ _ _ message -> modifyIORef' logs (<> [convert (fromLogStr message)]))
      (try action)
  (result,) <$> readIORef logs

-- | フィクスチャのリモートを既定の置き場所へ購読する引数。
arguments :: Fixture -> [String]
arguments fixture = [convert (remoteUrlText fixture.remoteUrl), fixture.subscription, "blob:none"]

tests :: TopSpec
tests = describe "run" do
  it "無いリポジトリをcloneして成功で終わる" do
    withFixture \fixture -> do
      runCapturing (run (arguments fixture)) >>= (`shouldBe` (Right (), []))
      doesDirectoryExist (fixture.subscription </> ".git") >>= (`shouldBe` True)
  it "fast-forwardできない時は警告を出して成功で終わる" do
    withFixture \fixture -> do
      (cloned, _) <- runCapturing (run (arguments fixture))
      cloned `shouldBe` Right ()
      localHead <- commitLocally fixture
      pushUpdate fixture "remote\n" "remote"
      (result, logs) <- runCapturing (run (arguments fixture))
      result `shouldBe` Right ()
      filter (isInfixOf "unable to fast-forward") logs `shouldBe` logs
      length logs `shouldBe` 1
      gitTextIn fixture.subscription ["rev-parse", "HEAD"] >>= (`shouldBe` localHead)
  it "originが無い時は警告を出して成功で終わる" do
    withFixture \fixture -> do
      (cloned, _) <- runCapturing (run (arguments fixture))
      cloned `shouldBe` Right ()
      gitIn fixture.subscription ["remote", "remove", "origin"]
      initialHead <- gitTextIn fixture.subscription ["rev-parse", "HEAD"]
      (result, logs) <- runCapturing (run (arguments fixture))
      result `shouldBe` Right ()
      filter (isInfixOf "has no origin remote") logs `shouldBe` logs
      length logs `shouldBe` 1
      gitTextIn fixture.subscription ["rev-parse", "HEAD"] >>= (`shouldBe` initialHead)
  it "URLとして読めない引数は1で終わり、置き場所を作らない" do
    withFixture \fixture -> do
      let destination = fixture.root </> "invalid-argument"
      -- 使い方はoptparse-applicativeが標準エラー出力へ直接出すので、こちらのログには何も出ない。
      runCapturing (run ["not a url", destination, "blob:none"])
        >>= (`shouldBe` (Left (ExitFailure 1), []))
      doesPathExist destination >>= (`shouldBe` False)
  it "cloneに失敗したらGitの終了コードで終わり、置き場所を作らない" do
    withFixture \fixture -> do
      let destination = fixture.root </> "failed-subscription"
      (result, logs) <-
        runCapturing (run ["file://" <> fixture.root </> "missing.git", destination, "blob:none"])
      -- 説明はGit自身が標準エラー出力へ出すので、こちらのログには何も足さない。
      -- `git clone`は届かないリモートに128で終わる。
      (result, logs) `shouldBe` (Left (ExitFailure 128), [])
      doesPathExist destination >>= (`shouldBe` False)
