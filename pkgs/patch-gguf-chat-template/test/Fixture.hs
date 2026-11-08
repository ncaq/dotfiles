-- | テストで使う小さなGGUFの組み立て。
--
-- 実物は22GB級なので、同じ構造を持つ小さなGGUFを組み立てて検査する。
-- テンプレートの前に可変長の値を置いて読み飛ばしの誤りがオフセットに出るようにし、
-- 後ろにも項目を置いて書き戻しが範囲を越えていないことを見られるようにする。
module Fixture
  ( architecture
  , tokens
  , tensorData
  , encodeWord32
  , encodeWord64
  , encodeString
  , encodeKv
  , architectureEntry
  , quantizationEntry
  , tokensEntry
  , tokenTypeEntry
  , templateEntry
  , fileTypeEntry
  , entries
  , header
  , assemble
  , buildGguf
  , withGgufFile
  ) where

import Data.Bits (Bits, shiftR)
import Data.ByteString qualified as B
import Himari
import PatchGgufChatTemplate.Gguf.Format
  ( GgufValueType (..)
  , encodeValueType
  , ggufMagic
  , ggufVersion
  )

architecture :: ByteString
architecture = "qwen3"

tokens :: [ByteString]
tokens = ["a", "bb", "ccc"]

tensorData :: ByteString
tensorData = "tensor-data-placeholder"

-- | リトルエンディアンで指定のバイト数に並べる。
-- 下位のバイトから順に取り出すので、収まらない上位は捨てる。
littleEndian :: (Bits a, Integral a) => Int -> a -> ByteString
littleEndian width value = B.pack [fromIntegral (value `shiftR` (8 * i)) | i <- [0 .. width - 1]]

encodeWord32 :: Word32 -> ByteString
encodeWord32 = littleEndian 4

encodeWord64 :: Word64 -> ByteString
encodeWord64 = littleEndian 8

-- | 長さプレフィックス付きの文字列を組み立てる。
encodeString :: ByteString -> ByteString
encodeString value = encodeWord64 (fromIntegral (B.length value)) <> value

-- | メタデータの1項目を組み立てる。
encodeKv :: ByteString -> GgufValueType -> ByteString -> ByteString
encodeKv key valueType payload =
  encodeString key <> encodeWord32 (encodeValueType valueType) <> payload

architectureEntry :: ByteString
architectureEntry = encodeKv "general.architecture" GgufString (encodeString architecture)

-- | uint32の固定長。
quantizationEntry :: ByteString
quantizationEntry = encodeKv "general.quantization_version" GgufUInt32 (encodeWord32 2)

-- | 文字列の配列。
-- 要素ごとに長さが違うので1つずつ読み飛ばす経路を通る。
tokensEntry :: ByteString
tokensEntry =
  encodeKv "tokenizer.ggml.tokens" GgufArray $
    encodeWord32 (encodeValueType GgufString)
      <> encodeWord64 (fromIntegral (length tokens))
      <> foldMap encodeString tokens

-- | int32の配列。
-- まとめて読み飛ばす経路を通る。
-- 要素数を引数にするのは、実際の要素数と違う値を書いたファイルを組み立てるためである。
tokenTypeEntry :: Word64 -> ByteString
tokenTypeEntry count =
  encodeKv "tokenizer.ggml.token_type" GgufArray $
    encodeWord32 (encodeValueType GgufInt32)
      <> encodeWord64 count
      <> foldMap (const (encodeWord32 1)) tokens

templateEntry :: ByteString -> ByteString
templateEntry template = encodeKv "tokenizer.chat_template" GgufString (encodeString template)

-- | テンプレートより後ろに置く項目。
fileTypeEntry :: ByteString
fileTypeEntry = encodeKv "general.file_type" GgufUInt32 (encodeWord32 18)

-- | 標準の並び。
-- `Nothing`ならチャットテンプレートの項目自体を持たない。
entries :: Maybe ByteString -> [ByteString]
entries template =
  [architectureEntry, quantizationEntry, tokensEntry, tokenTypeEntry (fromIntegral (length tokens))]
    <> foldMap (pure . templateEntry) template
    <> [fileTypeEntry]

-- | ヘッダ。
-- マジックナンバー、バージョン、テンソル数、メタデータ数の順に並ぶ。
header :: Word32 -> Word64 -> ByteString
header version kvCount = ggufMagic <> encodeWord32 version <> encodeWord64 0 <> encodeWord64 kvCount

-- | 項目を並べてGGUF全体にする。
assemble :: Word32 -> [ByteString] -> ByteString
assemble version kvs = header version (fromIntegral (length kvs)) <> mconcat kvs <> tensorData

-- | テンプレートを含む最小のGGUFを組み立てる。
buildGguf :: Maybe ByteString -> ByteString
buildGguf = assemble ggufVersion . entries

-- | GGUFを一時ディレクトリへ置いて、そのパスとテンプレートを置くためのパスを渡す。
withGgufFile :: (MonadUnliftIO m) => ByteString -> (FilePath -> FilePath -> m a) -> m a
withGgufFile content action =
  withSystemTempDirectory "patch-gguf-chat-template" \dir -> do
    let ggufPath = dir </> "model.gguf"
    writeBinaryFile ggufPath content
    action ggufPath (dir </> "chat_template.jinja")
