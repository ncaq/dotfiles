-- | 想定している失敗の型。
module GarageSetup.Failure
  ( ConfigFailure (..)
  , ApiFailure (..)
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

-- | HTTPは通ったが、Admin APIの応答を使えなかった。
data ApiFailure
  = -- | 成功ではない状態コードが返った。パスと状態コードを持つ。
    UnexpectedStatus Text Int
  | -- | 応答を期待した形のJSONとして読めなかった。パスとデコーダの理由を持つ。
    UndecodableBody Text Text
  deriving stock (Eq, Show)

instance Exception ApiFailure where
  displayException = \case
    UnexpectedStatus path status -> convert path <> "が状態コード" <> show status <> "を返しました"
    UndecodableBody path reason -> convert path <> "の応答を読めませんでした: " <> convert reason
