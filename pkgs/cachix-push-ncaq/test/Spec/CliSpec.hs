-- | 設定の読み取りから終了までのテスト。
module Spec.CliSpec (tests) where

import CachixPushNcaq.AuthToken (AuthToken)
import CachixPushNcaq.CacheName (CacheName)
import CachixPushNcaq.Cli (runWith)
import CachixPushNcaq.Failure (SecretsFailure (..))
import CachixPushNcaq.Tools (Tools (..))
import Data.Text (isInfixOf)
import Himari
import Test.Sandwich

-- | ログを端末へ出さずに集めて、結果と共に返す。
runCapturing :: (MonadIO m) => Himari SimpleEnv a -> m (Either ExitCode a, [Text])
runCapturing action = do
  logs <- newIORef []
  result <-
    runSimpleEnvWith
      (\_ _ _ message -> modifyIORef' logs (<> [convert (fromLogStr message)]))
      (try action)
  (result,) <$> readIORef logs

-- | 偽のコマンドが受け取った呼び出し。
data Call
  = Decrypt FilePath
  | Push AuthToken CacheName [String]
  deriving stock (Eq, Show)

-- | 呼び出しを記録して、決まったトークンを復号し、指定の終了コードで転送を終える偽のコマンド。
recordingTools :: (MonadIO m) => IORef [Call] -> ExitCode -> Tools m
recordingTools calls exitCode =
  Tools
    { decrypt = \path -> "token-example" <$ record (Decrypt path)
    , push = \token cache args -> exitCode <$ record (Push token cache args)
    }
 where
  record call = modifyIORef' calls (<> [call])

-- | 一時ディレクトリに置いたシークレットファイルを指す、環境変数を引く関数を作って実行する。
withSecretsFile :: (MonadUnliftIO m) => (FilePath -> (Text -> Maybe Text) -> m a) -> m a
withSecretsFile action =
  withSystemTempDirectory "cachix-push-ncaq-test" \directory -> do
    let path = directory </> "cachix.yaml"
    liftIO (writeFile path "")
    action path (secretsAt path)

-- | 指定のパスをシークレットファイルとする、環境変数を引く関数。
secretsAt :: FilePath -> Text -> Maybe Text
secretsAt path = \case
  "CACHIX_PUSH_NCAQ_SECRETS_FILE" -> Just (convert path)
  _ -> Nothing

tests :: TopSpec
tests = describe "runWith" do
  it "復号したトークンと引数を転送へ渡して成功で終わる" do
    withSecretsFile \path lookupVariable -> do
      calls <- newIORef []
      let args = ["/nix/store/a", "-j8"]
      runCapturing (runWith (recordingTools calls ExitSuccess) lookupVariable args)
        >>= (`shouldBe` (Right (), []))
      readIORef calls >>= (`shouldBe` [Decrypt path, Push "token-example" "ncaq" args])
  it "転送が失敗したらその終了コードで終わる" do
    withSecretsFile \_ lookupVariable -> do
      calls <- newIORef []
      runCapturing (runWith (recordingTools calls (ExitFailure 3)) lookupVariable [])
        >>= (`shouldBe` (Left (ExitFailure 3), []))
  it "シークレットファイルが無ければ復号を呼ばずに理由を出して1で終わる" do
    withSystemTempDirectory "cachix-push-ncaq-test" \directory -> do
      let path = directory </> "missing.yaml"
      calls <- newIORef []
      (result, logs) <-
        runCapturing (runWith (recordingTools calls ExitSuccess) (secretsAt path) [])
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      filter (isInfixOf (convert path)) logs `shouldBe` logs
      readIORef calls >>= (`shouldBe` [])
  it "復号が失敗したら転送を呼ばずに理由を出して1で終わる" do
    withSecretsFile \path lookupVariable -> do
      calls <- newIORef []
      let tools =
            (recordingTools calls ExitSuccess)
              { decrypt = \file -> throwM (DecryptFailed file (ExitFailure 128))
              }
      (result, logs) <- runCapturing (runWith tools lookupVariable [])
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      filter (isInfixOf (convert path)) logs `shouldBe` logs
      readIORef calls >>= (`shouldBe` [])
  it "設定が揃わなければ理由を出して1で終わる" do
    calls <- newIORef []
    (result, logs) <- runCapturing (runWith (recordingTools calls ExitSuccess) (const Nothing) [])
    result `shouldBe` Left (ExitFailure 1)
    length logs `shouldBe` 1
    filter (isInfixOf "HOME") logs `shouldBe` logs
    readIORef calls >>= (`shouldBe` [])
