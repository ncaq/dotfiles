-- | GGUFの形式で決まっている値。
--
-- GGUFはマジックナンバー、バージョン、テンソル数、メタデータ数のヘッダの後に、
-- メタデータのキーと値が長さプレフィックス付きで並び、
-- その後ろにテンソルの情報とテンソル本体が続く。
-- 値は型IDに続いて型ごとの表現で置かれる。
--
-- 対応するのはGGUF v3だけ。
-- v2以前はメタデータの長さがuint32で、読み方から違う。
module PatchGgufChatTemplate.Gguf.Format
  ( GgufValueType (..)
  , decodeValueType
  , encodeValueType
  , fixedSize
  , ggufMagic
  , ggufVersion
  , chatTemplateKey
  ) where

import Data.Bits (FiniteBits, finiteBitSize, zeroBits)
import Himari

ggufMagic :: ByteString
ggufMagic = "GGUF"

ggufVersion :: Word32
ggufVersion = 3

-- | 書き換える対象のメタデータのキー。
chatTemplateKey :: ByteString
chatTemplateKey = "tokenizer.chat_template"

-- | メタデータの値の型。
--
-- 構築子はGGUFの型IDの順に並べてあり、`fromEnum`がそのまま型IDになる。
-- 可変長なのは`GgufString`と`GgufArray`だけで、残りは`fixedSize`の幅を持つ。
data GgufValueType
  = GgufUInt8
  | GgufInt8
  | GgufUInt16
  | GgufInt16
  | GgufUInt32
  | GgufInt32
  | GgufFloat32
  | GgufBool
  | GgufString
  | GgufArray
  | GgufUInt64
  | GgufInt64
  | GgufFloat64
  deriving stock (Bounded, Enum, Eq, Show)

-- | ファイルに書かれた型IDを読む。知らないIDなら`Nothing`。
decodeValueType :: Word32 -> Maybe GgufValueType
decodeValueType = toEnumMay . fromIntegral

-- | ファイルに書く型ID。
encodeValueType :: GgufValueType -> Word32
encodeValueType = fromIntegral . fromEnum

-- | 固定長の値のバイト数。
-- 可変長の`GgufString`と`GgufArray`は`Nothing`。
--
-- 整数は対応するHaskellの型の幅から取る。
-- 浮動小数点はIEEE 754のbinary32とbinary64、真偽値は1バイトと仕様が決めているので、
-- 対応するHaskellの型の表現には寄らずにその値を書く。
fixedSize :: GgufValueType -> Maybe Int
fixedSize = \case
  GgufUInt8 -> Just (byteWidth (Proxy @Word8))
  GgufInt8 -> Just (byteWidth (Proxy @Int8))
  GgufUInt16 -> Just (byteWidth (Proxy @Word16))
  GgufInt16 -> Just (byteWidth (Proxy @Int16))
  GgufUInt32 -> Just (byteWidth (Proxy @Word32))
  GgufInt32 -> Just (byteWidth (Proxy @Int32))
  GgufFloat32 -> Just 4
  GgufBool -> Just 1
  GgufString -> Nothing
  GgufArray -> Nothing
  GgufUInt64 -> Just (byteWidth (Proxy @Word64))
  GgufInt64 -> Just (byteWidth (Proxy @Int64))
  GgufFloat64 -> Just 8

-- | 固定幅の整数型のバイト数。
byteWidth :: forall a. (FiniteBits a) => Proxy a -> Int
byteWidth _ = finiteBitSize (zeroBits :: a) `div` 8
