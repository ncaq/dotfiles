-- | 想定している失敗の型。
module UserSettingsSync.Failure
  ( ConfigFailure (..)
  , DeclarationFailure (..)
  , ApiFailure (..)
  , SyncFailure (..)
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

-- | 宣言のファイルを使えない理由。
data DeclarationFailure
  = -- | JSONのオブジェクトとして読めなかった。パスとデコーダの理由を持つ。
    UndecodableDeclaration FilePath Text
  deriving stock (Eq, Show)

instance Exception DeclarationFailure where
  displayException = \case
    UndecodableDeclaration path reason ->
      path <> "をJSONのオブジェクトとして読めませんでした: " <> convert reason

-- | HTTPは通ったが、APIの応答を使えなかった。
data ApiFailure
  = -- | 成功ではない状態コードが返った。パスと状態コードを持つ。
    UnexpectedStatus Text Int
  | -- | 応答を期待した形のJSONとして読めなかった。パスとデコーダの理由を持つ。
    UndecodableBody Text Text
  | -- | サインインの応答にトークンが無かった。
    MissingToken
  deriving stock (Eq, Show)

instance Exception ApiFailure where
  displayException = \case
    UnexpectedStatus path status -> convert path <> "が状態コード" <> show status <> "を返しました"
    UndecodableBody path reason -> convert path <> "の応答を読めませんでした: " <> convert reason
    MissingToken -> "サインインの応答からトークンを取り出せませんでした"

-- | 同期しても宣言と実体が揃わなかった。
data SyncFailure
  = -- | Open WebUIが上限まで待っても応答しなかった。
    HealthTimedOut
  | -- | プロフィールを更新しても宣言と一致しなかった。
    ProfileNotConverged
  deriving stock (Eq, Show)

instance Exception SyncFailure where
  displayException = \case
    HealthTimedOut -> "Open WebUIが応答するのを待ちましたが、時間切れになりました"
    ProfileNotConverged ->
      "プロフィールを更新しても宣言と一致しませんでした。"
        <> "宣言に上流が受け付けない列が含まれている可能性があります"
