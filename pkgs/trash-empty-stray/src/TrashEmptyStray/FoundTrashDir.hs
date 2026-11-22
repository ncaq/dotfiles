-- | 探索が見つけたゴミ箱と、それがどのディレクトリだったかの控え。
module TrashEmptyStray.FoundTrashDir
  ( FoundTrashDir (..)
  , DirIdentity (..)
  , identityOf
  ) where

import Himari
import System.Posix.Files (FileStatus, deviceID, fileID)
import System.Posix.Types (DeviceID, FileID)
import TrashEmptyStray.AbsDir (AbsDir)

-- | ディレクトリの実体を見分けるための、デバイスとinode番号の組。
--
-- パスは、途中のディレクトリを差し替えれば別の実体を指すようにできる。
-- この組が同じなら、パスがどう変わっていても同じ実体である。
data DirIdentity = DirIdentity
  { device :: DeviceID
  , inode :: FileID
  }
  deriving stock (Eq, Ord, Show)

-- | ファイルの情報から、実体を見分けるための組を取り出す。
identityOf :: FileStatus -> DirIdentity
identityOf status = DirIdentity{device = deviceID status, inode = fileID status}

-- | 探索が見つけたゴミ箱。
--
-- 見つけた時の実体を控えておき、掃除のために開いた時に同じ実体かを確かめる。
-- 探索は、ホームのゴミ箱の中や別のデバイスのような、降りないと決めた場所を除いている。
-- 見つけてから開くまでの間に途中のディレクトリをシンボリックリンクへ差し替えられると、
-- 除いたはずの場所にあるゴミ箱を開いてしまうためである。
data FoundTrashDir = FoundTrashDir
  { path :: AbsDir
  , identity :: DirIdentity
  }
  deriving stock (Eq, Ord, Show)
