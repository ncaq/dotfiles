-- | `cachix-push-ncaq`の、設定の読み取りから終了までのテスト。
module Spec.Cachix.CliSpec (tests) where

import Data.Text (isInfixOf)
import Fixture (failingSops, recordingSops, runCapturing, variables, withSecretsFile)
import Himari
import NixCachePushNcaq.AuthToken (AuthToken)
import NixCachePushNcaq.Cachix.CacheName (CacheName)
import NixCachePushNcaq.Cachix.Cli (runWith)
import NixCachePushNcaq.Cachix.Command (Cachix (..))
import Test.Sandwich

-- | 呼び出しを記録して、指定の終了コードで転送を終える偽の`cachix`。
recordingCachix :: (MonadIO m) => IORef [(AuthToken, CacheName, [String])] -> ExitCode -> Cachix m
recordingCachix calls exitCode =
  Cachix
    { push = \token cache args -> exitCode <$ modifyIORef' calls (<> [(token, cache, args)])
    }

-- | 指定のパスをシークレットファイルとする、環境変数を引く関数。
secretsAt :: FilePath -> Text -> Maybe Text
secretsAt path = variables [("CACHIX_PUSH_NCAQ_SECRETS_FILE", convert path)]

tests :: TopSpec
tests = describe "runWith" do
  it "復号したトークンと引数を転送へ渡して成功で終わる" do
    withSecretsFile \path -> do
      decrypts <- newIORef []
      pushes <- newIORef []
      let args = ["/nix/store/a", "-j8"]
      runCapturing
        ( runWith
            (recordingSops decrypts)
            (recordingCachix pushes ExitSuccess)
            (secretsAt path)
            args
        )
        >>= (`shouldBe` (Right (), []))
      readIORef decrypts >>= (`shouldBe` [("CACHIX_AUTH_TOKEN", path)])
      readIORef pushes >>= (`shouldBe` [("token-example", "ncaq", args)])
  it "転送が失敗したらその終了コードで終わる" do
    withSecretsFile \path -> do
      decrypts <- newIORef []
      pushes <- newIORef []
      runCapturing
        ( runWith
            (recordingSops decrypts)
            (recordingCachix pushes (ExitFailure 3))
            (secretsAt path)
            []
        )
        >>= (`shouldBe` (Left (ExitFailure 3), []))
  it "シークレットファイルが無ければ復号を呼ばずに理由を出して1で終わる" do
    withSecretsFile \existing -> do
      let path = existing <> ".missing"
      decrypts <- newIORef []
      pushes <- newIORef []
      (result, logs) <-
        runCapturing
          ( runWith
              (recordingSops decrypts)
              (recordingCachix pushes ExitSuccess)
              (secretsAt path)
              []
          )
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      filter (isInfixOf (convert path)) logs `shouldBe` logs
      readIORef decrypts >>= (`shouldBe` [])
      readIORef pushes >>= (`shouldBe` [])
  it "復号が失敗したら転送を呼ばずに理由を出して1で終わる" do
    withSecretsFile \path -> do
      pushes <- newIORef []
      (result, logs) <-
        runCapturing (runWith failingSops (recordingCachix pushes ExitSuccess) (secretsAt path) [])
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      filter (isInfixOf (convert path)) logs `shouldBe` logs
      readIORef pushes >>= (`shouldBe` [])
  it "設定が揃わなければ理由を出して1で終わる" do
    decrypts <- newIORef []
    pushes <- newIORef []
    (result, logs) <-
      runCapturing
        (runWith (recordingSops decrypts) (recordingCachix pushes ExitSuccess) (variables []) [])
    result `shouldBe` Left (ExitFailure 1)
    length logs `shouldBe` 1
    filter (isInfixOf "HOME") logs `shouldBe` logs
    readIORef decrypts >>= (`shouldBe` [])
    readIORef pushes >>= (`shouldBe` [])
