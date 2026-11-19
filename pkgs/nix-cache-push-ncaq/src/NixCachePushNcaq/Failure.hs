-- | 想定している失敗の型。
module NixCachePushNcaq.Failure
  ( ConfigFailure (..)
  , SecretsFailure (..)
  ) where

import Data.List (intercalate)
import Himari

-- | 設定を揃えられない理由。
data ConfigFailure
  = -- | 必要な環境変数が無いか空である。その名前。
    MissingVariable Text
  | -- | 認証トークンの一時ファイルを置けるディレクトリが無い。調べた候補を持つ。
    --
    -- 候補が存在しない場合と、存在してもtmpfsの上に無い場合の両方を含む。
    NoTmpfsDirectory [FilePath]
  | -- | マウントの一覧を読めなかった。パーサの理由を持つ。
    UnparsableMountInfo Text
  deriving stock (Eq, Show)

instance Exception ConfigFailure where
  displayException = \case
    MissingVariable name -> "環境変数" <> convert name <> "が必要です"
    NoTmpfsDirectory candidates ->
      "認証トークンの一時ファイルを置けません。"
        <> "候補のどれも、存在するtmpfsの上のディレクトリではありません: "
        <> intercalate ", " candidates
    UnparsableMountInfo reason -> "マウントの一覧を読めませんでした: " <> convert reason

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
