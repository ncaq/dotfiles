-- | Garageがバケットへ振るID。
module GarageSetup.BucketId
  ( BucketId (..)
  ) where

import Himari

newtype BucketId = BucketId Text
  deriving stock (Eq, Show)
  deriving newtype (FromJSON, IsString, ToJSON)
