-- | Admin APIへ送る内容のテスト。
module Spec.CallSpec (tests) where

import GarageSetup.Call
import Himari
import Test.Sandwich

tests :: TopSpec
tests = do
  describe "clusterHealth" do
    it "クラスタの状態を取る" do
      clusterHealth
        `shouldBe` Call{method = Get, path = "/v2/GetClusterHealth", query = [], body = Nothing}
  describe "createKey" do
    it "名前と、秒までのUTCの期限を送る" do
      createKey "niks3-public" (posixSecondsToUTCTime 1700000000.987)
        `shouldBe` Call
          { method = Post
          , path = "/v2/CreateKey"
          , query = []
          , body =
              Just [aesonQQ|{"name": "niks3-public", "expiration": "2023-11-14T22:13:20Z"}|]
          }
  describe "bucketInfo" do
    it "グローバルエイリアスをクエリで送る" do
      bucketInfo "niks3-public"
        `shouldBe` Call
          { method = Get
          , path = "/v2/GetBucketInfo"
          , query = [("globalAlias", "niks3-public")]
          , body = Nothing
          }
  describe "createBucket" do
    it "グローバルエイリアスを付けて作る" do
      createBucket "niks3-public"
        `shouldBe` Call
          { method = Post
          , path = "/v2/CreateBucket"
          , query = []
          , body = Just [aesonQQ|{"globalAlias": "niks3-public"}|]
          }
  describe "allowBucketKey" do
    it "読み書きの両方を許可する" do
      allowBucketKey "bucket-id" "GKtest"
        `shouldBe` Call
          { method = Post
          , path = "/v2/AllowBucketKey"
          , query = []
          , body =
              Just
                [aesonQQ|{
                  "bucketId": "bucket-id",
                  "accessKeyId": "GKtest",
                  "permissions": {"read": true, "write": true}
                }|]
          }
  describe "abortIncompleteUploads" do
    it "未完了のマルチパートアップロードを2日後に中止するルールを設定する" do
      abortIncompleteUploads "bucket-id"
        `shouldBe` Call
          { method = Post
          , path = "/v2/UpdateBucket"
          , query = [("id", "bucket-id")]
          , body =
              Just
                [aesonQQ|{
                  "lifecycleRules": [
                    {
                      "ID": "abort-incomplete-multipart-upload",
                      "Status": "Enabled",
                      "Filter": {"Prefix": ""},
                      "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 2}
                    }
                  ]
                }|]
          }
