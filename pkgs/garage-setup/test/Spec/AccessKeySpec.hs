-- | `CreateKey`の応答の読み方のテスト。
module Spec.AccessKeySpec (tests) where

import GarageSetup.AccessKey (AccessKey (..), SecretAccessKey)
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "AccessKey" do
  it "IDと秘密の側を読む" do
    eitherDecode "{\"accessKeyId\":\"GKtest\",\"secretAccessKey\":\"secret\",\"name\":\"x\"}"
      `shouldBe` Right AccessKey{accessKeyId = "GKtest", secretAccessKey = "secret"}
  for_
    [ ("IDが空", "{\"accessKeyId\":\"\",\"secretAccessKey\":\"secret\"}")
    , ("秘密の側が空", "{\"accessKeyId\":\"GKtest\",\"secretAccessKey\":\"\"}")
    , ("IDがnull", "{\"accessKeyId\":null,\"secretAccessKey\":\"secret\"}")
    , ("秘密の側が無い", "{\"accessKeyId\":\"GKtest\"}")
    , ("オブジェクトではない", "[]")
    ]
    \(name, response) ->
      it (name <> "なら読まない") do
        isLeft (eitherDecode response :: Either String AccessKey) `shouldBe` True
  it "秘密の側は表示しても中身を出さない" do
    show ("secret" :: SecretAccessKey) `shouldBe` "SecretAccessKey <redacted>"
    show (AccessKey "GKtest" "secret").secretAccessKey `shouldBe` "SecretAccessKey <redacted>"
