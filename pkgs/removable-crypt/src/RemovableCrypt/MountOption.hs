-- | `mount -o`へ渡すマウントオプション。
module RemovableCrypt.MountOption
  ( MountOption (..)
  , joinMountOptions
  ) where

import Data.Text qualified as T
import Himari

newtype MountOption = MountOption Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | `mount -o`の引数の形にまとめる。
joinMountOptions :: [MountOption] -> Text
joinMountOptions = T.intercalate "," . coerce
