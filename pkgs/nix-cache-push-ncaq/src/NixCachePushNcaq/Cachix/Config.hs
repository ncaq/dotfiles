-- | `cachix-push-ncaq`が起動時に受け取る設定。環境変数から受け取る。
--
-- * `CACHIX_PUSH_NCAQ_SECRETS_FILE`: sopsで暗号化されたシークレットファイル。
--   無ければ`$HOME/dotfiles/secrets/cachix.yaml`を使う。
-- * `CACHIX_PUSH_NCAQ_CACHE`: Cachixのキャッシュの名前。無ければ`ncaq`を使う。
module NixCachePushNcaq.Cachix.Config
  ( Config (..)
  , configFrom
  ) where

import Himari
import NixCachePushNcaq.Cachix.CacheName (CacheName (..), defaultCacheName)
import NixCachePushNcaq.Variable (present, required)

data Config = Config
  { secretsFile :: FilePath
  , cacheName :: CacheName
  }
  deriving stock (Eq, Show)

-- | 環境変数を引く関数から設定を組み立てる。空は無いのと同じに扱う。
--
-- シークレットファイルの指定も`HOME`も無ければ`MissingVariable`を投げる。
configFrom :: (MonadThrow m) => (Text -> Maybe Text) -> m Config
configFrom lookupVariable =
  Config
    <$> maybe defaultSecretsFile (pure . convert) (variable "CACHIX_PUSH_NCAQ_SECRETS_FILE")
    <*> pure (maybe defaultCacheName CacheName (variable "CACHIX_PUSH_NCAQ_CACHE"))
 where
  defaultSecretsFile =
    (</> "dotfiles" </> "secrets" </> "cachix.yaml") . convert <$> required lookupVariable "HOME"
  variable = present lookupVariable
