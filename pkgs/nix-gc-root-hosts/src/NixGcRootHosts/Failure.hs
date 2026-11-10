-- | 想定している失敗の型。
module NixGcRootHosts.Failure
  ( ConfigFailure (..)
  , NixFailure (..)
  ) where

import Himari

-- | 設定を揃えられない理由。
newtype ConfigFailure
  = -- | 必要な環境変数が無いか空である。その名前。
    MissingVariable Text
  deriving stock (Eq, Show)

instance Exception ConfigFailure where
  displayException = \case
    MissingVariable name -> "環境変数" <> convert name <> "が必要です"

-- | Nixの出力を使えない理由。
data NixFailure
  = -- | 属性の名前の一覧をJSONとして読めなかった。属性とデコーダの理由を持つ。
    UndecodableAttrNames Text Text
  deriving stock (Eq, Show)

instance Exception NixFailure where
  displayException = \case
    UndecodableAttrNames attribute reason ->
      convert attribute <> "の名前の一覧を読めませんでした: " <> convert reason
