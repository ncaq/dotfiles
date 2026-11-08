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
  , GgufLayout (..)
  , layout
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
-- それぞれの値がファイルにどう置かれるかは`layout`が決める。
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

-- | 値がファイルにどう置かれるか。
--
-- 読み飛ばす側はこれで分岐するので、
-- 置かれ方の分からない型は型として存在しない。
data GgufLayout
  = -- | 決まったバイト数がそのまま置かれる。
    GgufFixedWidth Int
  | -- | uint64の長さプレフィックスの後にその長さのバイト列が置かれる。
    GgufLengthPrefixed
  | -- | 要素の型IDとuint64の要素数の後に、要素がその数だけ置かれる。
    GgufElements
  deriving stock (Eq, Show)

-- | 値の置かれ方。
--
-- 整数の幅は対応するHaskellの型の幅から取る。
-- 浮動小数点はIEEE 754のbinary32とbinary64、真偽値は1バイトと仕様が決めているので、
-- 対応するHaskellの型の表現には寄らずにその値を書く。
layout :: GgufValueType -> GgufLayout
layout = \case
  GgufUInt8 -> GgufFixedWidth (byteWidth (Proxy @Word8))
  GgufInt8 -> GgufFixedWidth (byteWidth (Proxy @Int8))
  GgufUInt16 -> GgufFixedWidth (byteWidth (Proxy @Word16))
  GgufInt16 -> GgufFixedWidth (byteWidth (Proxy @Int16))
  GgufUInt32 -> GgufFixedWidth (byteWidth (Proxy @Word32))
  GgufInt32 -> GgufFixedWidth (byteWidth (Proxy @Int32))
  GgufFloat32 -> GgufFixedWidth 4
  GgufBool -> GgufFixedWidth 1
  GgufString -> GgufLengthPrefixed
  GgufArray -> GgufElements
  GgufUInt64 -> GgufFixedWidth (byteWidth (Proxy @Word64))
  GgufInt64 -> GgufFixedWidth (byteWidth (Proxy @Int64))
  GgufFloat64 -> GgufFixedWidth 8

-- | 固定幅の整数型のバイト数。
byteWidth :: forall a. (FiniteBits a) => Proxy a -> Int
byteWidth _ = finiteBitSize (zeroBits :: a) `div` 8
