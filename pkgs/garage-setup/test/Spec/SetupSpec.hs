-- | バケットとキーの用意を通しで行うテスト。
--
-- Admin APIは決まった応答を返して呼び出しを記録するだけの偽物に差し替える。
module Spec.SetupSpec (tests) where

import GarageSetup.Call (Call (..), Method (..))
import GarageSetup.Failure (ApiFailure (..))
import GarageSetup.Setup (Environment (..), setup)
import Himari
import Test.Sandwich

-- | 通信そのものの失敗を表す、偽のAdmin APIの例外。
data ConnectionLost = ConnectionLost
  deriving stock (Eq, Show)

instance Exception ConnectionLost

-- | 偽のAdmin APIがバケットの情報の問い合わせへ返すもの。
data BucketLookup
  = Found
  | -- | 成功ではない状態コードを返す。無いバケットを引いた時がこれに当たる。
    NotFound
  | -- | 応答を返す前に通信が切れる。
    Disconnected
  | -- | 成功の状態コードで、JSONとして読めない本文を返す。
    Garbled
  | -- | 成功の状態コードで、IDの無い本文を返す。
    WithoutId

-- | 用意した結果。
data Ending
  = Done
  | ApiFailed ApiFailure
  | -- | 通信そのものの失敗で終わった。
    ConnectionFailed
  | -- | 想定していない例外で終わった。
    Crashed
  deriving stock (Eq, Show)

-- | 偽のAdmin APIの振る舞い。
data Behavior = Behavior
  { healthFailures :: Int
  -- ^ 状態の問い合わせが、最初に何回失敗するか。
  , bucketLookup :: BucketLookup
  , keyResponse :: Value
  }

-- | すぐに応答して、バケットは既にある。
healthy :: Behavior
healthy =
  Behavior
    { healthFailures = 0
    , bucketLookup = Found
    , keyResponse = [aesonQQ|{"accessKeyId": "GKtest", "secretAccessKey": "secret"}|]
    }

-- | 用意して、結果と、送った呼び出しの宛先と、書き出したキーファイルを返す。
--
-- 呼び出しは本文を除いて返す。本文は`Spec.CallSpec`が固定している。
prepared
  :: (MonadUnliftIO m)
  => Behavior
  -> m (Ending, [(Method, Text, [(Text, Text)])], [(FilePath, Text)])
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
          "/v2/GetBucketInfo" -> case behavior.bucketLookup of
            Found -> pure [aesonQQ|{"id": "existing-bucket"}|]
            NotFound -> throwM (UnexpectedStatus call.path 404)
            Disconnected -> throwM ConnectionLost
            Garbled -> throwM (UndecodableBody call.path "not json")
            WithoutId -> pure [aesonQQ|{"message": "ok"}|]
          "/v2/CreateBucket" -> pure [aesonQQ|{"id": "new-bucket"}|]
          _ -> pure Null
      environment =
        Environment
          { transport
          , -- 待たずに最大3回まで問い合わせ直す。
            healthRetry = limitRetries 3
          , writeKeyFile = \file content -> modifyIORef' files (<> [(file, content)])
          }
  result <- runSimpleNoLogEnv (tryAny (setup environment "niks3-public"))
  (classify result,,) <$> readIORef calls <*> readIORef files
 where
  classify = \case
    Right () -> Done
    Left exception
      | Just failure <- fromException exception -> ApiFailed failure
      | Just ConnectionLost <- fromException exception -> ConnectionFailed
      | otherwise -> Crashed

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
              ( Done
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
    prepared healthy{bucketLookup = NotFound}
      >>= ( `shouldBe`
              ( Done
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
    result `shouldBe` Done
    take 4 calls `shouldBe` [health, health, health, createKey]
    files `shouldBe` keyFiles
  it "待ってもGarageが応答しなければ、キーを作らずに失敗する" do
    prepared healthy{healthFailures = 10}
      >>= ( `shouldBe`
              ( ApiFailed (UnexpectedStatus "/v2/GetClusterHealth" 503)
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
        (result == Done) `shouldBe` False
        calls `shouldBe` [health, createKey]
        files `shouldBe` []
  for_
    [ ("通信が切れた", Disconnected, ConnectionFailed)
    , ("本文を読めなかった", Garbled, ApiFailed (UndecodableBody "/v2/GetBucketInfo" "not json"))
    ]
    \(name, lookupResult, expected) ->
      it ("バケットの情報を取る時に" <> name <> "なら、バケットを作りに行かずに失敗する") do
        -- 無いと分かった時にだけ作る。分からない時に作りに行くと、
        -- 一時的な不調のたびに作成の要求が飛ぶ。
        prepared healthy{bucketLookup = lookupResult}
          >>= (`shouldBe` (expected, [health, createKey, bucketInfo], keyFiles))
  it "バケットの情報にIDが無ければ、バケットを作りに行かずに失敗する" do
    (result, calls, _) <- prepared healthy{bucketLookup = WithoutId}
    (result == Done) `shouldBe` False
    calls `shouldBe` [health, createKey, bucketInfo]
