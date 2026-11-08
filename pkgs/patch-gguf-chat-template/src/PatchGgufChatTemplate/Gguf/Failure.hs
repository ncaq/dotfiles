-- | GGUFを読んでいる途中で分かった、そのファイルを扱えない理由。
--
-- 投げるのは"PatchGgufChatTemplate.Gguf.Reader"と"PatchGgufChatTemplate.Gguf.Value"と、
-- "PatchGgufChatTemplate.Gguf.Locate"で、
-- どれが投げても呼び出し側は同じ型で受けられるようにここへまとめる。
module PatchGgufChatTemplate.Gguf.Failure
  ( GgufFailure (..)
  ) where

import Himari
import PatchGgufChatTemplate.Gguf.Format (GgufValueType)

-- | 読んでいる途中で分かった、このファイルを扱えない理由。
data GgufFailure
  = -- | マジックナンバーが違う。
    NotGguf
  | -- | 対応していないバージョン。
    UnexpectedVersion Word32
  | -- | 途中で切れたファイル。欲しかったバイト数と、読めたバイト数。
    UnexpectedEndOfFile Int Int
  | -- | 長さプレフィックスがファイルの残りに収まらない。宣言された長さと、残りのバイト数。
    LengthExceedsFile Integer Integer
  | -- | 知らない型ID。
    UnknownValueType Word32
  | -- | 固定長でも文字列でもない要素を持つ配列。
    UnsupportedElementType GgufValueType
  | -- | チャットテンプレートが文字列ではない。
    ChatTemplateNotString GgufValueType
  | -- | チャットテンプレートが無い。
    ChatTemplateNotFound
  deriving stock (Eq, Show)

instance Exception GgufFailure where
  displayException = \case
    NotGguf -> "GGUFファイルではありません"
    UnexpectedVersion version -> "対応していないGGUFのバージョンです: " <> show version
    UnexpectedEndOfFile wanted got ->
      "ファイルが途中で切れています: "
        <> show wanted
        <> "バイト必要なところ"
        <> show got
        <> "バイトしか読めませんでした"
    LengthExceedsFile declared remaining ->
      "長さ" <> show declared <> "がファイルの残り" <> show remaining <> "バイトを超えています"
    UnknownValueType raw -> "知らない値の型IDです: " <> show raw
    UnsupportedElementType elementType ->
      "対応していない配列の要素の型です: " <> show elementType
    ChatTemplateNotString valueType ->
      "tokenizer.chat_templateが文字列ではありません: " <> show valueType
    ChatTemplateNotFound -> "tokenizer.chat_templateがありません"
