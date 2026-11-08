-- | GGUFのメタデータを走査して`tokenizer.chat_template`の位置を求める。
--
-- ヘッダを確かめてから、メタデータの項目を先頭から順に見ていき、
-- 目的のキーが現れるまで値を"PatchGgufChatTemplate.Gguf.Value"で読み飛ばす。
-- 読むのはメタデータの数MBだけで、テンソルには触れない。
module PatchGgufChatTemplate.Gguf.Locate
  ( Span (..)
  , locateChatTemplate
  ) where

import Data.ByteString qualified as B
import Himari
import PatchGgufChatTemplate.Gguf.Failure (GgufFailure (..))
import PatchGgufChatTemplate.Gguf.Format
  ( GgufValueType (..)
  , chatTemplateKey
  , ggufMagic
  , ggufVersion
  )
import PatchGgufChatTemplate.Gguf.Reader
  ( readLength
  , readString
  , readValueType
  , readWord32
  , readWord64
  )
import PatchGgufChatTemplate.Gguf.Value (skipValue)

-- | 値の位置。
data Span = Span
  { offset :: Integer
  -- ^ ファイル先頭からのバイト数。
  , size :: Int
  -- ^ バイト長。
  }
  deriving stock (Eq, Show)

-- | `tokenizer.chat_template`の値の位置を求める。
--
-- 返る時、ハンドルはその値の先頭で止まっている。
-- 呼び出し側はそのまま読むか書くかできる。
locateChatTemplate :: (MonadIO m, MonadThrow m) => Handle -> m Span
locateChatTemplate file = do
  magic <- liftIO (B.hGet file 4)
  when (magic /= ggufMagic) $ throwM NotGguf
  version <- readWord32 file
  when (version /= ggufVersion) $ throwM (UnexpectedVersion version)
  -- ヘッダはテンソル数とメタデータ数がこの順に並ぶ。
  -- テンソルは読まないので数だけ捨てる。
  _tensorCount <- readWord64 file
  kvCount <- readWord64 file
  search kvCount
 where
  search :: (MonadIO m, MonadThrow m) => Word64 -> m Span
  search 0 = throwM ChatTemplateNotFound
  search remainingKvs = do
    key <- readString file
    valueType <- readValueType file
    if key /= chatTemplateKey
      then do
        skipValue file valueType
        search (remainingKvs - 1)
      else do
        when (valueType /= GgufString) $ throwM (ChatTemplateNotString valueType)
        size <- readLength file
        offset <- hTell file
        pure Span{offset, size}
