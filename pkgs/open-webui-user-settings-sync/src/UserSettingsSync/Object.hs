-- | JSONのオブジェクトの読み方。
module UserSettingsSync.Object
  ( objectOf
  ) where

import Himari

-- | JSONのオブジェクトを`Map`として読む。オブジェクトでなければ`Nothing`にする。
objectOf :: Value -> Maybe (Map Text Value)
objectOf value = case fromJSON value of
  Success object -> Just object
  Error _ -> Nothing
