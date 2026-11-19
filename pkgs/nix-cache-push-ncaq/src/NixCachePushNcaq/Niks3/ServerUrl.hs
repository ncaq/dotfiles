-- | niks3サーバのURL。
module NixCachePushNcaq.Niks3.ServerUrl
  ( ServerUrl (..)
  ) where

import Himari

newtype ServerUrl = ServerUrl Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)
