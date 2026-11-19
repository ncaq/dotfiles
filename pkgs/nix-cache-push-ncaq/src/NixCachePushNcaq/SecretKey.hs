-- | シークレットファイルの中で、認証トークンを指すキー。
module NixCachePushNcaq.SecretKey
  ( SecretKey (..)
  ) where

import Himari

newtype SecretKey = SecretKey Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)
