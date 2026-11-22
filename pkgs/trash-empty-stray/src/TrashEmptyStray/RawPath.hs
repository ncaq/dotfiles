-- | 探索の間だけ使う、バイト列のままのパス。
module TrashEmptyStray.RawPath
  ( RawPath
  , toRawPath
  , fromRawPath
  , appendName
  ) where

import Data.ByteString qualified as B
import GHC.Foreign (peekCStringLen, withCString)
import GHC.IO.Encoding (getFileSystemEncoding)
import Himari

-- | カーネルが返すバイト列のままのパス。
--
-- 探索は百万を超えるディレクトリの名前を読む。
-- 1つずつ`FilePath`へ復号すると、復号の時間と文字のリストのメモリが所要時間の大半を占める。
-- 名前を見分けるだけならバイト列のままで足りるので、
-- 復号するのは見つけたゴミ箱を返す時だけにする。
type RawPath = ByteString

-- | `FilePath`をカーネルへ渡す時と同じ符号化でバイト列にする。
toRawPath :: (MonadIO m) => FilePath -> m RawPath
toRawPath path = liftIO do
  encoding <- getFileSystemEncoding
  withCString encoding path B.packCString

-- | カーネルから受け取った時と同じ復号で`FilePath`にする。
fromRawPath :: (MonadIO m) => RawPath -> m FilePath
fromRawPath path = liftIO do
  encoding <- getFileSystemEncoding
  B.useAsCStringLen path (peekCStringLen encoding)

-- | ディレクトリのパスへ、その中の名前を繋ぐ。
appendName :: RawPath -> ByteString -> RawPath
appendName directory name = directory <> "/" <> name
