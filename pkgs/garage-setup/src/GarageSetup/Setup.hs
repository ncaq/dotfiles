-- | バケットとキーを用意する。
--
-- Garageのバケットを使うサービスが起動する前に走る。
-- 起動のたびに新しいキーを作ってファイルへ書き出し、
-- バケットを無ければ作って、キーへ読み書きを許可する。
-- 何度走らせても同じ状態へ収束する。
module GarageSetup.Setup
  ( Environment (..)
  , keyLifetime
  , healthPolicy
  , setup
  ) where

import GarageSetup.AccessKey (AccessKey (..), AccessKeyId (..), SecretAccessKey (..))
import GarageSetup.BucketId (BucketId)
import GarageSetup.BucketName (BucketName)
import GarageSetup.Call
  ( abortIncompleteUploads
  , allowBucketKey
  , bucketInfo
  , clusterHealth
  , createBucket
  , createKey
  )
import GarageSetup.Failure (ApiFailure (..))
import GarageSetup.Transport (Transport)
import Himari

-- | 外の世界との接点。
data Environment m = Environment
  { transport :: Transport m
  , healthRetry :: RetryPolicyM m
  -- ^ Garageが応答するまでの待ち方。
  , writeKeyFile :: FilePath -> Text -> m ()
  -- ^ 名前と中身を受け取って、キーファイルを書き出す。
  }

-- | キーの寿命。
--
-- サービスは再起動のたびに新しいキーを受け取るので、
-- これより長く動き続けるサービスがあると期限切れになる。
keyLifetime :: NominalDiffTime
keyLifetime = 90 * nominalDay

-- | Garageが応答するまで、合計で1分ほど待つ。
--
-- コンテナが起動した直後はまだlistenしていない。
-- 最初は短い間隔で確かめて、間隔を2秒まで広げていく。
healthPolicy :: (MonadIO m) => RetryPolicyM m
healthPolicy = limitRetriesByCumulativeDelay 60000000 (capDelay 2000000 (fullJitterBackoff 100000))

-- | バケットとキーを用意する。
setup
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => Environment m -> BucketName -> m ()
setup environment name = do
  void (recoverAll environment.healthRetry (const (environment.transport clusterHealth)))
  expiresAt <- addUTCTime keyLifetime <$> liftIO getCurrentTime
  key :: AccessKey <- environment.transport (createKey name expiresAt) >>= decoded "/v2/CreateKey"
  let AccessKeyId accessKeyId = key.accessKeyId
      SecretAccessKey secretAccessKey = key.secretAccessKey
  environment.writeKeyFile "s3-access-key" accessKeyId
  environment.writeKeyFile "s3-secret-key" secretAccessKey
  bucket <- existingBucket >>= maybe newBucket pure
  void (environment.transport (allowBucketKey bucket key.accessKeyId))
  void (environment.transport (abortIncompleteUploads bucket))
  logInfoN ("バケットとキーを用意しました。キーのIDは" <> accessKeyId <> "です")
 where
  -- 既にあるバケットのIDを取る。
  --
  -- 無いバケットを引くとGarageは成功ではない状態コードを返すので、それを無いものとして扱う。
  -- 通信の失敗はここでは吸収せず、上へ通す。
  existingBucket =
    tryJust unexpectedStatus (environment.transport (bucketInfo name)) >>= \case
      Left _ -> pure Nothing
      Right response -> Just <$> bucketIdOf "/v2/GetBucketInfo" response
  newBucket = environment.transport (createBucket name) >>= bucketIdOf "/v2/CreateBucket"
  unexpectedStatus = \case
    failure@(UnexpectedStatus _ _) -> Just failure
    _ -> Nothing
  bucketIdOf path response = (.bucketId) <$> decoded @Bucket path response

-- | バケットを返す応答のうち、使う部分。
newtype Bucket = Bucket
  { bucketId :: BucketId
  }

instance FromJSON Bucket where
  parseJSON = withObject "Bucket" \o -> Bucket <$> o .: "id"

-- | 応答を期待した形として読む。読めなければ`ApiFailure`として投げる。
decoded :: forall a m. (FromJSON a, MonadThrow m) => Text -> Value -> m a
decoded path response = case fromJSON response of
  Success value -> pure value
  Error reason -> throwM (UndecodableBody path (convert reason))
