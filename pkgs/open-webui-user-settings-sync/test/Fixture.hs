-- | テストで共有する補助関数。
module Fixture
  ( fields
  ) where

import Himari

-- | JSONのオブジェクトを`Map`として読む。オブジェクトでなければ空にする。
--
-- 期待する値を`aesonQQ`で書いてから`Map`と比べるために使う。
fields :: Value -> Map Text Value
fields value = case fromJSON value of
  Success object -> object
  Error _ -> mempty
