-- | キーファイルの書き出しのテスト。
module Spec.KeyFileSpec (tests) where

import GarageSetup.KeyFile (writeSecretFile)
import Himari
import System.Posix.Files (fileMode, getFileStatus, intersectFileModes)
import Test.Sandwich

tests :: TopSpec
tests = describe "writeSecretFile" do
  it "中身をそのまま、末尾の改行を付けずに書く" do
    withSystemTempDirectory "garage-setup-test" \directory -> do
      let path = directory </> "s3-secret-key"
      writeSecretFile path "secret"
      liftIO (readFile path) >>= (`shouldBe` "secret")
  it "所有者だけが読めて、誰も書けないモードにする" do
    withSystemTempDirectory "garage-setup-test" \directory -> do
      let path = directory </> "s3-secret-key"
      writeSecretFile path "secret"
      status <- liftIO (getFileStatus path)
      intersectFileModes (fileMode status) 0o777 `shouldBe` 0o400
