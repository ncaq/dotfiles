-- | 復号したデバイスの中のファイルシステムの種類。
module RemovableCrypt.FilesystemType
  ( FilesystemType (..)
  , parseFilesystemType
  ) where

import Data.Text qualified as T
import Himari

data FilesystemType
  = -- | スナップショットを取れる。
    Btrfs
  | OtherFilesystem Text
  deriving stock (Eq, Show)

-- | `blkid -s TYPE -o value`の出力を読む。
parseFilesystemType :: Text -> FilesystemType
parseFilesystemType output = case T.strip output of
  "btrfs" -> Btrfs
  other -> OtherFilesystem other
