-- | 登録トークンの読み方のテスト。
module Spec.RegistrationTokenSpec (tests) where

import GithubRunnerRegistrationToken.RegistrationToken (RegistrationToken)
import Himari
import Test.Sandwich

-- | 応答の本文から登録トークンを読む。読めなければ`Nothing`にする。
decoded :: LazyByteString -> Maybe RegistrationToken
decoded content = eitherDecode content ^? _Right

tests :: TopSpec
tests = describe "RegistrationToken" do
  it "発行のAPIの応答からtokenを読む" do
    decoded "{\"token\": \"AABBCC\", \"expires_at\": \"2026-11-12T08:00:00.000Z\"}"
      `shouldBe` Just "AABBCC"
  it "tokenの無い応答は読めない" do
    decoded "{\"message\": \"Bad credentials\"}" `shouldBe` Nothing
  it "表示しても中身を出さない" do
    show ("AABBCC" :: RegistrationToken) `shouldBe` "RegistrationToken <redacted>"
