-- | テストで共有する補助関数。
module Fixture
  ( fields
  ) where

import Himari
import UserSettingsSync.Object (objectOf)

-- | JSONのオブジェクトを`Map`として読む。オブジェクトでなければ空にする。
--
-- 期待する値を`aesonQQ`で書いてから`Map`と比べるために使う。
fields :: Value -> Map Text Value
fields = fromMaybe mempty . objectOf
