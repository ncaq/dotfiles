-- | ゴミ箱の保持日数。
module TrashEmptyStray.RetentionDays
  ( RetentionDays (..)
  ) where

import Himari

-- | ゴミ箱へ入れてからこの日数が経ったものを消す。
newtype RetentionDays = RetentionDays Natural
  deriving stock (Eq, Show)
