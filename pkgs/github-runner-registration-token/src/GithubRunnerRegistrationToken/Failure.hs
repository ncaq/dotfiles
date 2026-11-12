-- | 想定している失敗の型。
module GithubRunnerRegistrationToken.Failure
  ( ConfigFailure (..)
  , ApiFailure (..)
  ) where

import Himari

-- | 設定を揃えられない理由。
data ConfigFailure
  = -- | 必要な環境変数が無いか空である。その名前。
    MissingVariable Text
  | -- | アクセストークンのファイルが空か、空白だけである。そのパス。
    EmptyAccessToken FilePath
  | -- | GitHubのAPIのURLとして読めない値が渡された。その値。
    InvalidApiUrl Text
  deriving stock (Eq, Show)

instance Exception ConfigFailure where
  displayException = \case
    MissingVariable name -> "環境変数" <> convert name <> "が必要です"
    EmptyAccessToken path -> "アクセストークンのファイル" <> path <> "が空です"
    InvalidApiUrl url -> "GitHubのAPIのURLとして読めません: " <> convert url

-- | GitHubのAPIから登録トークンを得られなかった。
data ApiFailure
  = -- | 接続できなかったか、応答を待ち切れなかった。http-clientの理由の表示を持つ。
    Unreachable Text
  | -- | 成功ではない状態コードが返った。状態コードと応答の本文を持つ。
    UnexpectedStatus Int Text
  | -- | 応答から登録トークンを読めなかった。デコーダの理由を持つ。
    UndecodableBody Text
  deriving stock (Eq, Show)

instance Exception ApiFailure where
  displayException = \case
    Unreachable reason -> "GitHubのAPIに接続できませんでした: " <> convert reason
    UnexpectedStatus status content ->
      "登録トークンの発行が状態コード" <> show status <> "を返しました: " <> convert content
    UndecodableBody reason -> "登録トークンの発行の応答を読めませんでした: " <> convert reason
