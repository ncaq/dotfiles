-- | 登録トークンのファイルへの書き出しのテスト。
module Spec.TokenFileSpec (tests) where

import GithubRunnerRegistrationToken.TokenFile (tokenFileName, writeTokenFile)
import Himari
import System.Posix.Files (fileMode, getFileStatus, intersectFileModes)
import Test.Sandwich

tests :: TopSpec
tests = describe "writeTokenFile" do
  it "中身をそのまま、末尾の改行を付けずに書く" do
    withSystemTempDirectory "github-runner-registration-token-test" \directory -> do
      let path = directory </> tokenFileName
      writeTokenFile path "AABBCC"
      liftIO (readFile path) >>= (`shouldBe` "AABBCC")
  it "所有者だけが読めて、誰も書けないモードにする" do
    withSystemTempDirectory "github-runner-registration-token-test" \directory -> do
      let path = directory </> tokenFileName
      writeTokenFile path "AABBCC"
      status <- liftIO (getFileStatus path)
      intersectFileModes (fileMode status) 0o777 `shouldBe` 0o400
  it "書けないモードの前のトークンを新しいトークンで置き換える" do
    withSystemTempDirectory "github-runner-registration-token-test" \directory -> do
      let path = directory </> tokenFileName
      writeTokenFile path "AABBCC"
      writeTokenFile path "DDEEFF"
      liftIO (readFile path) >>= (`shouldBe` "DDEEFF")
      status <- liftIO (getFileStatus path)
      intersectFileModes (fileMode status) 0o777 `shouldBe` 0o400
  it "置き換えた後に作業用のファイルを残さない" do
    withSystemTempDirectory "github-runner-registration-token-test" \directory -> do
      let path = directory </> tokenFileName
      writeTokenFile path "AABBCC"
      writeTokenFile path "DDEEFF"
      listDirectory directory >>= (`shouldBe` [tokenFileName])
