-- | バケットのグローバルエイリアス。
--
-- 利用するサービスの名前をそのまま使う。
-- キーの名前と、キーファイルを渡すユーザとグループの名前も兼ねる。
module GarageSetup.BucketName
  ( BucketName (..)
  ) where

import Himari

newtype BucketName = BucketName Text
  deriving stock (Eq, Show)
  deriving newtype (IsString, ToJSON)
