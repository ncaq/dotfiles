-- | 掃除するゴミ箱を指す2通りのパス。
module TrashEmptyStray.TrashDir
  ( TrashDir (..)
  , atPath
  ) where

import Himari

-- | 1つのゴミ箱の、中身を指すパスと自身を指すパス。
--
-- 所有者の権限で掃除する時は、確かめたディレクトリへ移動してから`.`で中身を指す。
-- 親のディレクトリを後から差し替えられても、確かめた実体を掴んだままにするためである。
-- 移動した先のディレクトリ自体は`.`では消せないので、消す時だけ見つけた時のパスを使う。
data TrashDir = TrashDir
  { inside :: FilePath
  -- ^ `info`と`files`を辿る時の起点。
  , self :: FilePath
  -- ^ 空になったゴミ箱自体を消す時のパス。
  }
  deriving stock (Eq, Show)

-- | 移動せずに、同じパスで中身も自身も指す。
atPath :: FilePath -> TrashDir
atPath path = TrashDir{inside = path, self = path}
