-- | S3のアクセスキー。
module GarageSetup.AccessKey
  ( AccessKey (..)
  , AccessKeyId (..)
  , SecretAccessKey (..)
  ) where

import Himari

-- | アクセスキーのID。秘密ではない。
newtype AccessKeyId = AccessKeyId Text
  deriving stock (Eq, Show)
  deriving newtype (FromJSON, IsString, ToJSON)

-- | アクセスキーの秘密の側。
--
-- 値ごと`show`してログや例外に出しても中身が漏れないように、`Show`は伏せる。
newtype SecretAccessKey = SecretAccessKey Text
  deriving stock (Eq)
  deriving newtype (FromJSON, IsString)

instance Show SecretAccessKey where
  show _ = "SecretAccessKey <redacted>"

-- | `CreateKey`が返すキー。
data AccessKey = AccessKey
  { accessKeyId :: AccessKeyId
  , secretAccessKey :: SecretAccessKey
  }
  deriving stock (Eq, Generic, Show)

-- | どちらかが空のキーは読まない。
--
-- 空のままファイルへ書くと、利用するサービスの側で原因の分かりにくい認証の失敗として現れる。
instance FromJSON AccessKey where
  parseJSON = withObject "AccessKey" \o -> do
    key <- AccessKey <$> o .: "accessKeyId" <*> o .: "secretAccessKey"
    when (key.accessKeyId == "" || key.secretAccessKey == "") (fail "キーが空です")
    pure key
