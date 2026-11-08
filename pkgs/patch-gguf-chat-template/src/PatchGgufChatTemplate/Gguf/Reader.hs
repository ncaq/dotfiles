-- | ファイルの残りと突き合わせながら読む基本操作。
--
-- 長さプレフィックスはファイルから読んだ値であり、
-- 壊れたファイルでは任意の値が入っている。
-- `hGet`へそのまま渡すと巨大なメモリ確保になり、
-- `hSeek`は末尾を越えても成功してしまう。
-- どちらもオフセットを静かに壊すので、
-- 長さは必ず`checkSpan`を通してから読むか読み飛ばす。
--
-- 22GB級のファイルを相手にするので、ファイル全体は読まない。
-- ハンドルから要るバイト数だけを順に読む。
module PatchGgufChatTemplate.Gguf.Reader
  ( readExact
  , readWord32
  , readWord64
  , readValueType
  , checkSpan
  , readLength
  , readString
  , skip
  ) where

import Data.Bits (toIntegralSized)
import Data.ByteString qualified as B
import Himari
import PatchGgufChatTemplate.Gguf.Failure (GgufFailure (..))
import PatchGgufChatTemplate.Gguf.Format (GgufValueType, decodeValueType)

-- | 指定したバイト数をちょうど読む。
--
-- 途中で切れたファイルでは`hGet`が短く返る。
-- そのまま数値として読むと別の値になってしまうので、足りなければ止める。
readExact :: (MonadIO m, MonadThrow m) => Handle -> Int -> m ByteString
readExact file wanted = do
  bytes <- liftIO (B.hGet file wanted)
  when (B.length bytes /= wanted) $ throwM (UnexpectedEndOfFile wanted (B.length bytes))
  pure bytes

-- | リトルエンディアンの符号なし整数として読む。
--
-- 右端のバイトから畳むので、最も内側で足される末尾のバイトが最上位になる。
littleEndian :: (Num a) => ByteString -> a
littleEndian = B.foldr' (\byte acc -> acc * 256 + fromIntegral byte) 0

readWord32 :: (MonadIO m, MonadThrow m) => Handle -> m Word32
readWord32 file = littleEndian <$> readExact file 4

readWord64 :: (MonadIO m, MonadThrow m) => Handle -> m Word64
readWord64 file = littleEndian <$> readExact file 8

-- | 値の型IDを読む。
-- 知らないIDは長さが分からず読み飛ばせないので止める。
readValueType :: (MonadIO m, MonadThrow m) => Handle -> m GgufValueType
readValueType file = do
  raw <- readWord32 file
  maybe (throwM (UnknownValueType raw)) pure (decodeValueType raw)

-- | これから読むか読み飛ばす長さがファイルの残りに収まっているか確かめて、`Int`で返す。
--
-- 掛け算を挟む呼び出し元のために`Integer`で受けて、桁あふれの余地を無くす。
-- 残りに収まる値はファイルサイズに収まるので、`Int`へ落としても欠けない。
checkSpan :: (MonadIO m, MonadThrow m) => Handle -> Integer -> m Int
checkSpan file declared = do
  remaining <- (-) <$> hFileSize file <*> hTell file
  case toIntegralSized declared of
    Just size | 0 <= declared && declared <= remaining -> pure size
    _ -> throwM (LengthExceedsFile declared remaining)

-- | 長さプレフィックスを1つ読んで検証する。
readLength :: (MonadIO m, MonadThrow m) => Handle -> m Int
readLength file = readWord64 file >>= checkSpan file . toInteger

-- | 長さプレフィックス付きの文字列を1つ読む。
readString :: (MonadIO m, MonadThrow m) => Handle -> m ByteString
readString file = readLength file >>= readExact file

-- | 検証済みの長さだけ読み飛ばす。
skip :: (MonadIO m) => Handle -> Int -> m ()
skip file size = hSeek file RelativeSeek (toInteger size)
