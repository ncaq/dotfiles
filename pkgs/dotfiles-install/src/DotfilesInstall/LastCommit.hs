-- | NixOSのブートエントリのラベルへ渡す、最新のコミットの情報。
--
-- `nixos/core/label.nix`がJSONとして読むので、フィールドの名前と型はそちらと揃える。
module DotfilesInstall.LastCommit
  ( LastCommit (..)
  ) where

import Himari

data LastCommit = LastCommit
  { subject :: Text
  -- ^ 最新のコミットの件名。
  , dirty :: Bool
  -- ^ このファイルを注入する前から、追跡しているファイルにコミットしていない変更があったか。
  -- stagingしただけの変更も含み、追跡していないファイルは含まない。
  , branch :: Text
  -- ^ 今のブランチの名前。
  }
  deriving stock (Eq, Generic, Show)
  deriving (ToJSON) via CustomJSON '[] LastCommit
