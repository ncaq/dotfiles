-- | `mount -o`へ渡すマウントオプション。
module RemovableCrypt.MountOption
  ( MountOption (..)
  , joinMountOptions
  , splitMountOptions
  ) where

import Data.Text qualified as T
import Himari

newtype MountOption = MountOption Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | `mount -o`の引数の形にまとめる。
joinMountOptions :: [MountOption] -> Text
joinMountOptions = T.intercalate "," . coerce

-- | カンマ区切りの文字列をマウントオプションに分ける。空の要素は捨てる。
--
-- オプションが1つも無いことは空文字列で表す。
splitMountOptions :: Text -> [MountOption]
splitMountOptions = fmap MountOption . filter (/= mempty) . T.splitOn ","
