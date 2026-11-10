-- | 利用者ごとの設定とプロフィールを、宣言した内容へ揃える。
--
-- 環境変数で宣言できるのはインスタンス全体の設定だけで、
-- 利用者ごとのデータへはHTTP APIで書き込むしかない。
--
-- 宣言と実体に差分がある時だけ書き込む。
-- コンテナが起動するたびに`updated_at`だけが進むのを避けるためである。
module UserSettingsSync.Sync
  ( Environment (..)
  , Declaration (..)
  , healthPolicy
  , healthLimit
  , sync
  ) where

import Himari
import UserSettingsSync.Call
  ( getProfile
  , getSettings
  , health
  , signIn
  , updateProfile
  , updateSettings
  )
import UserSettingsSync.Failure (ApiFailure (..), SyncFailure (..))
import UserSettingsSync.Profile (declaredColumns, desiredProfile)
import UserSettingsSync.Settings (currentUi, mergeUi)
import UserSettingsSync.Token (Token (..))
import UserSettingsSync.Transport (Transport)

-- | 外の世界との接点。
data Environment m = Environment
  { transport :: Transport m
  , healthRetry :: RetryPolicyM m
  -- ^ Open WebUIが応答するまでの待ち方。
  , healthLimit :: Int
  -- ^ 応答を待つ全体の上限。マイクロ秒。
  }

-- | 宣言した内容。
data Declaration = Declaration
  { settings :: Map Text Value
  -- ^ `settings.ui`へ重ねる鍵。
  , systemPrompt :: Text
  , profile :: Map Text Value
  -- ^ プロフィールの画像以外の列。
  , profileImage :: ByteString
  }
  deriving stock (Eq, Show)

-- | Open WebUIが応答するまで、合計で10分ほど待つ。
--
-- コンテナがbootした時点ではまだlistenしていない。
-- 埋め込みモデルの取得やDB migrationを伴う起動では待ち時間が長くなるので、
-- 接続が拒否される間も問い合わせ直して起動を待つ。
-- 最初は短い間隔で確かめて、間隔を2秒まで広げていく。
healthPolicy :: (MonadIO m) => RetryPolicyM m
healthPolicy = limitRetriesByCumulativeDelay 600000000 (capDelay 2000000 (fullJitterBackoff 100000))

-- | 応答を待つ全体の上限。10分。
--
-- `healthPolicy`の上限が数えるのは問い合わせの間の待ち時間だけで、
-- 1回の問い合わせにかかる時間は含まない。
-- 接続を受け付けたまま応答しない相手だと、1回ごとにHTTPの応答待ちの上限まで待つので、
-- 全体は10分を大きく超える。
-- 全体をこの上限で打ち切って、何を待って時間切れになったのかが分かる失敗にする。
healthLimit :: Int
healthLimit = 600000000

-- | 設定とプロフィールを宣言へ揃える。
sync :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => Environment m -> Declaration -> m ()
sync environment declaration = do
  timeout
    environment.healthLimit
    (recoverAll environment.healthRetry (const (environment.transport health)))
    >>= maybe (throwM HealthTimedOut) (const (pure ()))
  token <- environment.transport signIn >>= tokenOf
  syncSettings token
  syncProfile token
 where
  -- 応答が期待した形でなかった場合はここで落としておく。
  -- 空のトークンをそのまま使うと、
  -- 認証の失敗ではなく設定の取得の失敗として現れて原因が分かりにくい。
  tokenOf response = case fromJSON response of
    Success (fields :: Map Text Value)
      | Just (String token) <- fields ^? ix "token"
      , token /= mempty ->
          pure (Token token)
    _ -> throwM MissingToken
  syncSettings token = do
    current <- currentUi <$> environment.transport (getSettings token)
    let merged = mergeUi current declaration.settings declaration.systemPrompt
    if current == merged
      then logInfoN "利用者の設定は宣言と一致しています"
      else do
        void (environment.transport (updateSettings token merged))
        logInfoN "利用者の設定を宣言の内容へ更新しました"
  syncProfile token = do
    let desired = desiredProfile declaration.profile declaration.profileImage
        fetch = declaredColumns desired <$> environment.transport (getProfile token)
    current <- fetch
    if current == desired
      then logInfoN "プロフィールは宣言と一致しています"
      else do
        void (environment.transport (updateProfile token desired))
        -- `UpdateProfileForm`はPydanticのモデルなので、
        -- 宣言に上流が持たない列(将来の削除や綴り間違いを含む)が混ざると、
        -- 成功の状態コードが返ったまま値は黙って捨てられる。
        -- それに気付かないと差分は解消されず、
        -- コンテナが起動するたびに同じ書き込みが繰り返される。
        -- 書き込み後にもう一度取得して、収束したことまで確かめる。
        updated <- fetch
        unless (updated == desired) (throwM ProfileNotConverged)
        logInfoN "プロフィールを宣言の内容へ更新しました"
