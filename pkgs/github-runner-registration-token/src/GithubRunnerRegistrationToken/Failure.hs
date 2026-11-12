-- | 想定している失敗の型。
module GithubRunnerRegistrationToken.Failure
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

-- | HTTPは通ったが、GitHubのAPIの応答を使えなかった。
data ApiFailure
  = -- | 成功ではない状態コードが返った。状態コードと応答の本文を持つ。
    UnexpectedStatus Int Text
  | -- | 応答から登録トークンを読めなかった。デコーダの理由を持つ。
    UndecodableBody Text
  deriving stock (Eq, Show)

instance Exception ApiFailure where
  displayException = \case
    UnexpectedStatus status content ->
      "登録トークンの発行が状態コード" <> show status <> "を返しました: " <> convert content
    UndecodableBody reason -> "登録トークンの発行の応答を読めませんでした: " <> convert reason
