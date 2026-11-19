-- | Cachixのキャッシュの名前。
module CachixPushNcaq.CacheName
  ( CacheName (..)
  , defaultCacheName
  ) where

import Himari

newtype CacheName = CacheName Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | 指定が無い時に転送する先。
defaultCacheName :: CacheName
defaultCacheName = "ncaq"
