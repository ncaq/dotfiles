-- | 認証トークンの一時ファイルのテスト。
module Spec.Niks3.TokenFileSpec (tests) where

import Data.Text.IO.Utf8 (readFile)
import Himari hiding (readFile)
import NixCachePushNcaq.Niks3.TokenFile (withTokenFile)
import System.Posix.Files (fileMode, getFileStatus, intersectFileModes)
import Test.Sandwich

-- | 一時ファイルを置くディレクトリを作って渡す。
withDirectory :: (MonadUnliftIO m) => (FilePath -> m a) -> m a
withDirectory = withSystemTempDirectory "nix-cache-push-ncaq-test"

-- | 処理の途中で投げる例外。
data Interrupted = Interrupted
  deriving stock (Eq, Show)

instance Exception Interrupted

tests :: TopSpec
tests = describe "withTokenFile" do
  it "指定のディレクトリに、トークンだけを書いたファイルを作る" do
    withDirectory \directory ->
      withTokenFile directory "token-example" \path -> do
        takeDirectory path `shouldBe` directory
        liftIO (readFile path) >>= (`shouldBe` "token-example")
  it "所有者だけが読み書きできる" do
    withDirectory \directory ->
      withTokenFile directory "token-example" \path -> do
        status <- liftIO (getFileStatus path)
        intersectFileModes (fileMode status) 0o777 `shouldBe` 0o600
  it "処理が終わったら消す" do
    withDirectory \directory -> do
      path <- withTokenFile directory "token-example" pure
      doesFileExist path >>= (`shouldBe` False)
      listDirectory directory >>= (`shouldBe` [])
  it "処理が例外で終わっても消す" do
    withDirectory \directory -> do
      withTokenFile directory "token-example" (const (throwM Interrupted))
        `shouldThrow` (== Interrupted)
      listDirectory directory >>= (`shouldBe` [])
