-- | `locateChatTemplate`のテスト。
--
-- 確かめるのは、可変長の値を挟んでも目的のキーへ辿り着けることと、
-- 壊れたファイルで走査を続けずに止まることの2点である。
-- 長さプレフィックスを信じて読み進めると、
-- 目的のキーへ辿り着けないまま別の位置を書き換えるのが最悪の壊れ方になる。
--
-- 読み飛ばしと基本操作の失敗もここから通す。
-- どちらもファイルの中の位置が無ければ意味を持たないので、
-- 単体で呼ぶより組み立てたGGUFを渡して結果で見る方が、何が壊れたかを読み取れる。
module Spec.Gguf.LocateSpec (tests) where

import Data.ByteString qualified as B
import Fixture
import Himari
import PatchGgufChatTemplate.Gguf.Failure (GgufFailure (..))
import PatchGgufChatTemplate.Gguf.Format (GgufValueType (..), encodeValueType, ggufVersion)
import PatchGgufChatTemplate.Gguf.Locate (Span (..), locateChatTemplate)
import Test.Sandwich

template :: ByteString
template = "{{- 'ok' }}"

-- | ファイル全体より大きい長さ。1TiB。
hugeLength :: Word64
hugeLength = 2 ^ (40 :: Int)

-- | GGUFをファイルへ置いて位置を求める。
locate :: (MonadThrow m, MonadUnliftIO m) => ByteString -> m Span
locate content =
  withGgufFile content \ggufPath _ -> withBinaryFile ggufPath ReadMode locateChatTemplate

-- | 壊れた項目の長さプレフィックスを読み終えた位置から末尾までの残り。
--
-- 走査がその項目へ辿り着くまでに読むのは、ヘッダと手前の項目の全てと、
-- その項目のキーと型IDと長さプレフィックスである。
remainingAfterLength :: [ByteString] -> ByteString -> ByteString -> Integer
remainingAfterLength kvs broken prefixOfBroken =
  toInteger (B.length (assembleEntries kvs) - B.length consumed)
 where
  consumed =
    header ggufVersion (fromIntegral (length kvs))
      <> mconcat (takeWhile (/= broken) kvs)
      <> prefixOfBroken

tests :: TopSpec
tests = describe "locateChatTemplate" do
  it "可変長の値を挟んでもテンプレートの位置を返す" do
    let content = buildGguf (Just template)
        (prefix, _) = B.breakSubstring template content
    locate content
      >>= (`shouldBe` Span{offset = toInteger (B.length prefix), size = B.length template})
  it "テンプレートを持たないGGUFは黙って素通りせずに止まる" do
    locate (buildGguf Nothing) `shouldThrow` (== ChatTemplateNotFound)
  it "テンプレートが文字列でなければ止まる" do
    let content =
          assembleEntries
            [ architectureEntry
            , encodeKv "tokenizer.chat_template" GgufUInt32 (encodeWord32 7)
            , fileTypeEntry
            ]
    locate content `shouldThrow` (== ChatTemplateNotString GgufUInt32)
  it "v2以前は読み方から違うので受け付けない" do
    locate (assemble 2 (entries (Just template))) `shouldThrow` (== UnexpectedVersion 2)
  it "マジックナンバーが違うファイルは読まない" do
    locate ("NOTGGUF" <> buildGguf (Just template)) `shouldThrow` (== NotGguf)
  it "知らない型IDは読み飛ばせないので止まる" do
    -- 型IDは0から12まで。
    let unknown = encodeString "x" <> encodeWord32 13
    locate (assembleEntries [unknown, templateEntry template])
      `shouldThrow` (== UnknownValueType 13)
  it "配列の配列は読み飛ばせないので止まる" do
    let nested =
          encodeKv "x" GgufArray (encodeWord32 (encodeValueType GgufArray) <> encodeWord64 0)
    locate (assembleEntries [nested, templateEntry template])
      `shouldThrow` (== UnsupportedElementType GgufArray)
  it "ファイル末尾を超える長さの文字列は読まずに止まる" do
    -- テンプレートより手前の項目の長さだけを、ファイル全体より大きい値へ差し替える。
    let broken =
          encodeKv "general.architecture" GgufString (encodeWord64 hugeLength <> architecture)
        kvs = replacing architectureEntry broken (entries (Just template))
        remaining =
          remainingAfterLength kvs broken $
            encodeString "general.architecture"
              <> encodeWord32 (encodeValueType GgufString)
              <> encodeWord64 hugeLength
    locate (assembleEntries kvs)
      `shouldThrow` (== LengthExceedsFile (toInteger hugeLength) remaining)
  it "固定長配列の要素数がファイル末尾を超えていたら止まる" do
    -- 固定長の要素はまとめて読み飛ばすので、`hSeek`は末尾を越えても成功してしまう。
    -- 要素数の側で止めないと気付けない。
    let broken = tokenTypeEntry hugeLength
        original = tokenTypeEntry (fromIntegral (length tokens))
        kvs = replacing original broken (entries (Just template))
        remaining =
          remainingAfterLength kvs broken $
            encodeString "tokenizer.ggml.token_type"
              <> encodeWord32 (encodeValueType GgufArray)
              <> encodeWord32 (encodeValueType GgufInt32)
              <> encodeWord64 hugeLength
    locate (assembleEntries kvs)
      `shouldThrow` (== LengthExceedsFile (4 * toInteger hugeLength) remaining)
  it "途中で切れたファイルは何バイト足りなかったかを言って止まる" do
    -- ヘッダの24バイトの直後、最初のキーの長さプレフィックスの途中で切る。
    locate (B.take 30 (buildGguf (Just template))) `shouldThrow` (== UnexpectedEndOfFile 8 6)
