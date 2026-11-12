-- | 設定の読み取りからファイルへの書き出しまでの通しと、終了の仕方のテスト。
module Spec.CliSpec (tests) where

import Data.Text (isInfixOf)
import Fixture
import GithubRunnerRegistrationToken.Cli (runWith)
import GithubRunnerRegistrationToken.TokenFile (tokenFileName)
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

-- | 一時ディレクトリにアクセストークンのファイルを置いて、揃っている設定と書き出し先を渡す。
--
-- 発行は偽のGitHubのAPIに対して、試し直さずに行う。
withSetting
  :: (MonadUnliftIO m)
  => Text
  -- ^ ランナーを登録するリポジトリ。
  -> ([(Text, Text)] -> FilePath -> m a)
  -> m a
withSetting repository action =
  withSystemTempDirectory "github-runner-registration-token-test" \directory ->
    withApi \api -> do
      let accessTokenFile = directory </> "pat"
          runtimeDirectory = directory </> "runtime"
      createDirectory runtimeDirectory
      liftIO (writeFile accessTokenFile "github_pat_example\n")
      action
        [ ("GITHUB_RUNNER_REGISTRATION_TOKEN_REPOSITORY", repository)
        , ("GITHUB_RUNNER_REGISTRATION_TOKEN_API", api)
        , ("GITHUB_RUNNER_REGISTRATION_TOKEN_ACCESS_TOKEN_FILE", convert accessTokenFile)
        , ("RUNTIME_DIRECTORY", convert runtimeDirectory)
        ]
        (runtimeDirectory </> tokenFileName)

-- | 試し直さずに実行する。
runOnce :: (MonadIO m) => [(Text, Text)] -> m (Either ExitCode (), [Text])
runOnce environment = runCapturing (runWith (limitRetries 0) (variables environment))

tests :: TopSpec
tests = describe "runWith" do
  it "発行したトークンをRUNTIME_DIRECTORYのtokenへ書いて成功で終わる" do
    withSetting "ncaq/dotfiles" \environment tokenFile -> do
      (result, _) <- runOnce environment
      result `shouldBe` Right ()
      liftIO (readFile tokenFile) >>= (`shouldBe` "AABBCC")
  it "ログにアクセストークンと登録トークンを出さない" do
    withSetting "ncaq/dotfiles" \environment _ -> do
      (_, logs) <- runOnce environment
      length logs `shouldBe` 1
      filter (\line -> any (`isInfixOf` line) ["github_pat_example", "AABBCC"]) logs
        `shouldBe` []
  it "環境変数が欠けていれば理由を出して1で終わり、ファイルを作らない" do
    withSetting "ncaq/dotfiles" \environment tokenFile -> do
      (result, logs) <-
        runOnce (filter ((/= "GITHUB_RUNNER_REGISTRATION_TOKEN_API") . fst) environment)
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      doesFileExist tokenFile >>= (`shouldBe` False)
  it "発行が失敗の状態コードを返せば理由を出して1で終わり、ファイルを作らない" do
    withSetting "ncaq/forbidden" \environment tokenFile -> do
      (result, logs) <- runOnce environment
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      doesFileExist tokenFile >>= (`shouldBe` False)
