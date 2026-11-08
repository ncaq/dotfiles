-- | メタデータの値を1つ読み飛ばす。
--
-- テンプレートの位置を知るには、そこまでの全ての値を正しく読み飛ばす必要がある。
-- 1バイトでもずれると別のメタデータやテンソルの位置を書き換えることになり、
-- 壊れたGGUFはロードするまで表面化しない。
-- そのため型ごとの置かれ方を`layout`で網羅的に分け、
-- 長さの分からない形に出会ったら推測せずに止まる。
module PatchGgufChatTemplate.Gguf.Value
  ( skipValue
  ) where

import Himari
import PatchGgufChatTemplate.Gguf.Failure (GgufFailure (..))
import PatchGgufChatTemplate.Gguf.Format (GgufLayout (..), GgufValueType, layout)
import PatchGgufChatTemplate.Gguf.Reader (checkSpan, readLength, readValueType, readWord64, skip)

-- | 型IDの直後に置かれた値を1つ読み飛ばす。
skipValue :: (MonadIO m, MonadThrow m) => Handle -> GgufValueType -> m ()
skipValue file valueType = case layout valueType of
  GgufFixedWidth width -> skipFixed width 1
  GgufLengthPrefixed -> readLength file >>= skip file
  GgufElements -> do
    elementType <- readValueType file
    count <- readWord64 file
    case layout elementType of
      GgufFixedWidth width -> skipFixed width (toInteger count)
      GgufLengthPrefixed -> skipStrings count
      -- 配列の配列はGGUFの仕様には書けるが実物を見たことがない。
      -- 黙って読み飛ばすとオフセットがずれるので、読めないと言って止まる。
      GgufElements -> throwM (UnsupportedElementType elementType)
 where
  -- 固定長の要素はまとめて飛ばせる。
  -- 要素数はファイルから読んだ信じられない値なので、
  -- 積を`Integer`で取ってから残りと突き合わせる。
  skipFixed :: (MonadIO m, MonadThrow m) => Int -> Integer -> m ()
  skipFixed width count = checkSpan file (toInteger width * count) >>= skip file
  -- 文字列の配列は要素ごとに長さが違うのでまとめては飛ばせない。
  -- `tokenizer.ggml.tokens`がこれで、語彙の数だけ繰り返す。
  -- 要素数が壊れていても、1要素ごとに残りと突き合わせるので末尾で止まる。
  skipStrings :: (MonadIO m, MonadThrow m) => Word64 -> m ()
  skipStrings 0 = pure ()
  skipStrings count = do
    readLength file >>= skip file
    skipStrings (count - 1)
