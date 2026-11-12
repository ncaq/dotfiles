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

-- | テストごとに用意する置き場所と、偽のGitHubのAPI。
data Workspace m = Workspace
  { environment :: [(Text, Text)]
  -- ^ 揃っている設定。
  , tokenFile :: FilePath
  -- ^ 登録トークンの書き出し先。
  , requests :: m Int
  -- ^ 偽のGitHubのAPIが受け取ったリクエストの数を読む。
  }

-- | 一時ディレクトリにアクセストークンのファイルを置いて、偽のGitHubのAPIを立てる。
withWorkspace
  :: (MonadUnliftIO m)
  => Text
  -- ^ ランナーを登録するリポジトリ。
  -> (Workspace m -> m a)
  -> m a
withWorkspace repository action =
  withSystemTempDirectory "github-runner-registration-token-test" \directory ->
    withCountedApi \api requests -> do
      let accessTokenFile = directory </> "pat"
          runtimeDirectory = directory </> "runtime"
      createDirectory runtimeDirectory
      liftIO (writeFile accessTokenFile "github_pat_example\n")
      action
        Workspace
          { environment =
              [ ("GITHUB_RUNNER_REGISTRATION_TOKEN_REPOSITORY", repository)
              , ("GITHUB_RUNNER_REGISTRATION_TOKEN_API", api)
              , ("GITHUB_RUNNER_REGISTRATION_TOKEN_ACCESS_TOKEN_FILE", convert accessTokenFile)
              , ("RUNTIME_DIRECTORY", convert runtimeDirectory)
              ]
          , tokenFile = runtimeDirectory </> tokenFileName
          , requests
          }

-- | 失敗したら間を置かずに2回まで試し直す設定で実行する。
runRetrying :: (MonadIO m) => [(Text, Text)] -> m (Either ExitCode (), [Text])
runRetrying environment = runCapturing (runWith (limitRetries 2) (variables environment))

tests :: TopSpec
tests = describe "runWith" do
  it "発行したトークンをRUNTIME_DIRECTORYのtokenへ書いて成功で終わる" do
    withWorkspace "ncaq/dotfiles" \workspace -> do
      (result, _) <- runRetrying workspace.environment
      result `shouldBe` Right ()
      liftIO (readFile workspace.tokenFile) >>= (`shouldBe` "AABBCC")
      workspace.requests >>= (`shouldBe` 1)
  it "ログにアクセストークンと登録トークンを出さない" do
    withWorkspace "ncaq/dotfiles" \workspace -> do
      (_, logs) <- runRetrying workspace.environment
      logs `shouldBe` ["登録トークンを発行しました: ncaq/dotfiles"]
      filter (\line -> any (`isInfixOf` line) ["github_pat_example", "AABBCC"]) logs
        `shouldBe` []
  it "環境変数が欠けていれば理由を出して1で終わり、ファイルを作らない" do
    withWorkspace "ncaq/dotfiles" \workspace -> do
      (result, logs) <-
        runRetrying
          (filter ((/= "GITHUB_RUNNER_REGISTRATION_TOKEN_API") . fst) workspace.environment)
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      doesFileExist workspace.tokenFile >>= (`shouldBe` False)
      workspace.requests >>= (`shouldBe` 0)
  it "失敗の状態コードは試し直して、成功すればトークンを書く" do
    withWorkspace "ncaq/flaky" \workspace -> do
      (result, _) <- runRetrying workspace.environment
      result `shouldBe` Right ()
      liftIO (readFile workspace.tokenFile) >>= (`shouldBe` "AABBCC")
      workspace.requests >>= (`shouldBe` 2)
  it "失敗の状態コードが続けば試し直しを使い切って1で終わり、ファイルを作らない" do
    withWorkspace "ncaq/forbidden" \workspace -> do
      (result, logs) <- runRetrying workspace.environment
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      doesFileExist workspace.tokenFile >>= (`shouldBe` False)
      workspace.requests >>= (`shouldBe` 3)
  it "読めない応答は試し直さずに1で終わり、ファイルを作らない" do
    withWorkspace "ncaq/garbled" \workspace -> do
      (result, logs) <- runRetrying workspace.environment
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      doesFileExist workspace.tokenFile >>= (`shouldBe` False)
      workspace.requests >>= (`shouldBe` 1)
