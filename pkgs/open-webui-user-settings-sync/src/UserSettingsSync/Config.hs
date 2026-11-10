-- | 起動時に受け取る設定。環境変数から受け取る。
--
-- * `OPEN_WEBUI_URL`: Open WebUIのURL。末尾に`/`は付けない。
-- * `OPEN_WEBUI_DECLARED_SETTINGS_FILE`: `settings.ui`へ重ねる鍵を書いたJSONファイル。
-- * `OPEN_WEBUI_SYSTEM_PROMPT_FILE`: システムプロンプトのテキストファイル。
-- * `OPEN_WEBUI_DECLARED_PROFILE_FILE`: プロフィールの列を書いたJSONファイル。
-- * `OPEN_WEBUI_PROFILE_IMAGE_FILE`: プロフィールのアイコンにするWebPの画像ファイル。
module UserSettingsSync.Config
  ( Config (..)
  , configFrom
  ) where

import Himari
import UserSettingsSync.Failure (ConfigFailure (..))

data Config = Config
  { url :: Text
  , declaredSettingsFile :: FilePath
  , systemPromptFile :: FilePath
  , declaredProfileFile :: FilePath
  , profileImageFile :: FilePath
  }
  deriving stock (Eq, Show)

-- | 環境変数を引く関数から設定を組み立てる。空は無いのと同じに扱う。
configFrom :: (Text -> Maybe Text) -> Either ConfigFailure Config
configFrom lookupVariable =
  Config
    <$> require "OPEN_WEBUI_URL"
    <*> file "OPEN_WEBUI_DECLARED_SETTINGS_FILE"
    <*> file "OPEN_WEBUI_SYSTEM_PROMPT_FILE"
    <*> file "OPEN_WEBUI_DECLARED_PROFILE_FILE"
    <*> file "OPEN_WEBUI_PROFILE_IMAGE_FILE"
 where
  file variable = convert <$> require variable
  require variable =
    maybe (Left (MissingVariable variable)) Right (mfilter (/= mempty) (lookupVariable variable))
