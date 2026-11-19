-- | 想定している失敗の型。
module NixCachePushNcaq.Failure
  ( ConfigFailure (..)
  , SecretsFailure (..)
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

-- | シークレットから認証トークンを得られない理由。
data SecretsFailure
  = -- | シークレットファイルが無い。そのパス。
    SecretsFileNotFound FilePath
  | -- | 復号するコマンドが失敗した。シークレットファイルのパスと終了コードを持つ。
    DecryptFailed FilePath ExitCode
  | -- | 復号した認証トークンが空である。
    EmptyAuthToken
  deriving stock (Eq, Show)

instance Exception SecretsFailure where
  displayException = \case
    SecretsFileNotFound path -> "シークレットファイル" <> path <> "がありません"
    DecryptFailed path code ->
      "シークレットファイル" <> path <> "を復号できませんでした: " <> show code
    EmptyAuthToken -> "復号した認証トークンが空です"
