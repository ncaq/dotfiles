-- | Admin APIのトークンの読み方のテスト。
module Spec.AdminTokenSpec (tests) where

import GarageSetup.AdminToken (AdminToken, readAdminToken)
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "AdminToken" do
  it "ファイルの末尾の改行を落として読む" do
    withSystemTempDirectory "garage-setup-test" \directory -> do
      let path = directory </> "token"
      liftIO (writeFile path "admin-token\n")
      readAdminToken path >>= (`shouldBe` "admin-token")
  it "表示しても中身を出さない" do
    show ("admin-token" :: AdminToken) `shouldBe` "AdminToken <redacted>"
