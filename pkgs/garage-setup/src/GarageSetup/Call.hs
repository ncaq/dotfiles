-- | Admin APIの1回の呼び出し。
--
-- 何を送るかを値として組み立ててから送るので、送る内容をHTTPに触れずに検査できる。
-- APIの仕様は<https://garagehq.deuxfleurs.fr/api/garage-admin-v2.html>にある。
module GarageSetup.Call
  ( Call (..)
  , Method (..)
  , clusterHealth
  , createKey
  , bucketInfo
  , createBucket
  , allowBucketKey
  , abortIncompleteUploads
  ) where

import GarageSetup.AccessKey (AccessKeyId)
import GarageSetup.BucketId (BucketId (..))
import GarageSetup.BucketName (BucketName (..))
import Himari

data Method
  = Get
  | Post
  deriving stock (Eq, Show)

data Call = Call
  { method :: Method
  , path :: Text
  , query :: [(Text, Text)]
  , body :: Maybe Value
  }
  deriving stock (Eq, Show)

-- | クラスタの状態を取る。応答が返ればGarageは起動している。
clusterHealth :: Call
clusterHealth = Call{method = Get, path = "/v2/GetClusterHealth", query = [], body = Nothing}

data CreateKeyRequest = CreateKeyRequest
  { name :: BucketName
  , expiration :: Text
  }
  deriving stock (Generic)
  deriving (ToJSON) via CustomJSON '[] CreateKeyRequest

-- | 期限付きのキーを作る。
--
-- キーは使い捨てで、起動のたびに新しく作る。
-- 古いキーは触らずに期限切れを待つ。
createKey :: BucketName -> UTCTime -> Call
createKey name expiresAt =
  Call
    { method = Post
    , path = "/v2/CreateKey"
    , query = []
    , body =
        Just
          ( toJSON
              CreateKeyRequest
                { name
                , expiration = convert (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" expiresAt)
                }
          )
    }

-- | グローバルエイリアスからバケットの情報を取る。
bucketInfo :: BucketName -> Call
bucketInfo (BucketName name) =
  Call{method = Get, path = "/v2/GetBucketInfo", query = [("globalAlias", name)], body = Nothing}

newtype CreateBucketRequest = CreateBucketRequest
  { globalAlias :: BucketName
  }
  deriving stock (Generic)
  deriving (ToJSON) via CustomJSON '[] CreateBucketRequest

-- | グローバルエイリアスを付けてバケットを作る。
createBucket :: BucketName -> Call
createBucket name =
  Call
    { method = Post
    , path = "/v2/CreateBucket"
    , query = []
    , body = Just (toJSON CreateBucketRequest{globalAlias = name})
    }

data AllowBucketKeyRequest = AllowBucketKeyRequest
  { bucketId :: BucketId
  , accessKeyId :: AccessKeyId
  , permissions :: Value
  }
  deriving stock (Generic)
  deriving (ToJSON) via CustomJSON '[] AllowBucketKeyRequest

-- | キーへバケットの読み書きを許可する。
allowBucketKey :: BucketId -> AccessKeyId -> Call
allowBucketKey bucketId accessKeyId =
  Call
    { method = Post
    , path = "/v2/AllowBucketKey"
    , query = []
    , body =
        Just
          ( toJSON
              AllowBucketKeyRequest
                { bucketId
                , accessKeyId
                , permissions = [aesonQQ|{"read": true, "write": true}|]
                }
          )
    }

-- | 未完了のマルチパートアップロードを2日後に自動で中止するlifecycleルールを設定する。
--
-- 未完了のマルチパートが溜まり続けるとメタデータDB(LMDB)が肥大化する。
-- Garage組み込みのlifecycle workerに日々掃除させて、負荷を平準化する。
-- workerはUTCの0時に100件ずつ処理する。件数と頻度はGarageのソースに固定されている。
-- アプリケーション側のGCと喧嘩しにくいように、期限は長めの2日にする。
abortIncompleteUploads :: BucketId -> Call
abortIncompleteUploads (BucketId bucketId) =
  Call
    { method = Post
    , path = "/v2/UpdateBucket"
    , query = [("id", bucketId)]
    , body =
        Just
          [aesonQQ|{
            "lifecycleRules": [
              {
                "ID": "abort-incomplete-multipart-upload",
                "Status": "Enabled",
                "Filter": { "Prefix": "" },
                "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 2 }
              }
            ]
          }|]
    }
