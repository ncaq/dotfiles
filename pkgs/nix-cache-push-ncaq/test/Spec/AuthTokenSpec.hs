-- | 認証トークンの読み方のテスト。
module Spec.AuthTokenSpec (tests) where

import Himari
import NixCachePushNcaq.AuthToken (AuthToken, authTokenFromOutput)
import NixCachePushNcaq.Failure (SecretsFailure (..))
import Test.Sandwich

tests :: TopSpec
tests = describe "AuthToken" do
  it "末尾の改行を落として読む" do
    authTokenFromOutput "token-example\n" >>= (`shouldBe` "token-example")
  it "CRLFの改行も落とす" do
    authTokenFromOutput "token-example\r\n" >>= (`shouldBe` "token-example")
  it "改行が無くても読む" do
    authTokenFromOutput "token-example" >>= (`shouldBe` "token-example")
  it "空の出力は失敗にする" do
    authTokenFromOutput "" `shouldThrow` (== EmptyAuthToken)
  it "改行だけの出力も失敗にする" do
    authTokenFromOutput "\n" `shouldThrow` (== EmptyAuthToken)
  it "表示しても中身を出さない" do
    show ("token-example" :: AuthToken) `shouldBe` "AuthToken <redacted>"
