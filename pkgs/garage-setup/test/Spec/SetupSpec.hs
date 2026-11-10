-- | バケットとキーの用意を通しで行うテスト。
--
-- Admin APIは決まった応答を返して呼び出しを記録するだけの偽物に差し替える。
module Spec.SetupSpec (tests) where

import GarageSetup.Call (Call (..), Method (..))
import GarageSetup.Failure (ApiFailure (..))
import GarageSetup.Setup (Environment (..), setup)
import Himari
import Test.Sandwich

-- | 偽のAdmin APIの振る舞い。
data Behavior = Behavior
  { healthFailures :: Int
  -- ^ 状態の問い合わせが、最初に何回失敗するか。
  , bucketExists :: Bool
  , keyResponse :: Value
  }

-- | すぐに応答して、バケットは既にある。
healthy :: Behavior
healthy =
  Behavior
    { healthFailures = 0
    , bucketExists = True
    , keyResponse = [aesonQQ|{"accessKeyId": "GKtest", "secretAccessKey": "secret"}|]
    }

-- | 用意して、結果と、送った呼び出しの宛先と、書き出したキーファイルを返す。
--
-- 呼び出しは本文を除いて返す。本文は`Spec.CallSpec`が固定している。
prepared
  :: (MonadUnliftIO m)
  => Behavior
  -> m (Either ApiFailure (), [(Method, Text, [(Text, Text)])], [(FilePath, Text)])
prepared behavior = do
  calls <- newIORef []
  files <- newIORef []
  remainingFailures <- newIORef behavior.healthFailures
  let transport call = do
        modifyIORef' calls (<> [(call.method, call.path, call.query)])
        case call.path of
          "/v2/GetClusterHealth" -> do
            unhealthy <-
              atomicModifyIORef' remainingFailures \count -> (max 0 (count - 1), 0 < count)
            when unhealthy (throwM (UnexpectedStatus call.path 503))
            pure [aesonQQ|{"status": "healthy"}|]
          "/v2/CreateKey" -> pure behavior.keyResponse
          "/v2/GetBucketInfo"
            | behavior.bucketExists -> pure [aesonQQ|{"id": "existing-bucket"}|]
            | otherwise -> throwM (UnexpectedStatus call.path 404)
          "/v2/CreateBucket" -> pure [aesonQQ|{"id": "new-bucket"}|]
          _ -> pure Null
      environment =
        Environment
          { transport
          , -- 待たずに最大3回まで問い合わせ直す。
            healthRetry = limitRetries 3
          , writeKeyFile = \file content -> modifyIORef' files (<> [(file, content)])
          }
  result <- runSimpleNoLogEnv (try (setup environment "niks3-public"))
  (result,,) <$> readIORef calls <*> readIORef files

health :: (Method, Text, [(Text, Text)])
health = (Get, "/v2/GetClusterHealth", [])

createKey :: (Method, Text, [(Text, Text)])
createKey = (Post, "/v2/CreateKey", [])

bucketInfo :: (Method, Text, [(Text, Text)])
bucketInfo = (Get, "/v2/GetBucketInfo", [("globalAlias", "niks3-public")])

keyFiles :: [(FilePath, Text)]
keyFiles = [("s3-access-key", "GKtest"), ("s3-secret-key", "secret")]

tests :: TopSpec
tests = describe "setup" do
  it "バケットが既にあれば、作らずにそのバケットへ許可とlifecycleを設定する" do
    prepared healthy
      >>= ( `shouldBe`
              ( Right ()
              ,
                [ health
                , createKey
                , bucketInfo
                , (Post, "/v2/AllowBucketKey", [])
                , (Post, "/v2/UpdateBucket", [("id", "existing-bucket")])
                ]
              , keyFiles
              )
          )
  it "バケットが無ければ作って、そのバケットへ設定する" do
    prepared healthy{bucketExists = False}
      >>= ( `shouldBe`
              ( Right ()
              ,
                [ health
                , createKey
                , bucketInfo
                , (Post, "/v2/CreateBucket", [])
                , (Post, "/v2/AllowBucketKey", [])
                , (Post, "/v2/UpdateBucket", [("id", "new-bucket")])
                ]
              , keyFiles
              )
          )
  it "Garageが応答するまで待ってから進む" do
    (result, calls, files) <- prepared healthy{healthFailures = 2}
    result `shouldBe` Right ()
    take 4 calls `shouldBe` [health, health, health, createKey]
    files `shouldBe` keyFiles
  it "待ってもGarageが応答しなければ、キーを作らずに失敗する" do
    prepared healthy{healthFailures = 10}
      >>= ( `shouldBe`
              ( Left (UnexpectedStatus "/v2/GetClusterHealth" 503)
              , [health, health, health, health]
              , []
              )
          )
  for_
    [ ("キーが空の", [aesonQQ|{"accessKeyId": "", "secretAccessKey": ""}|])
    , ("キーがnullの", [aesonQQ|{"accessKeyId": null, "secretAccessKey": null}|])
    , ("形の違う", [aesonQQ|{"message": "internal error"}|])
    ]
    \(name, response) ->
      it (name <> "応答なら、キーファイルを書かずに失敗する") do
        (result, calls, files) <- prepared healthy{keyResponse = response}
        isLeft result `shouldBe` True
        calls `shouldBe` [health, createKey]
        files `shouldBe` []
