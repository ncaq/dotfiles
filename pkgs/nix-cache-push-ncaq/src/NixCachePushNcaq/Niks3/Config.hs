-- | `niks3-push-ncaq`が起動時に受け取る設定。環境変数から受け取る。
--
-- 最初の2つは`package.nix`の作る`niks3-push-ncaq-{public,private}`が既定の値を設定する。
--
-- * `NIKS3_PUSH_NCAQ_SECRETS_FILE`: sopsで暗号化されたシークレットファイル。
-- * `NIKS3_PUSH_NCAQ_SERVER_URL`: niks3サーバのURL。
-- * `XDG_RUNTIME_DIR`: 認証トークンの一時ファイルを置くディレクトリ。
--   無ければシステムの一時ディレクトリを使う。
module NixCachePushNcaq.Niks3.Config
  ( Config (..)
  , configFrom
  ) where

import Himari
import NixCachePushNcaq.Niks3.ServerUrl (ServerUrl (..))
import NixCachePushNcaq.Variable (present, required)

data Config = Config
  { secretsFile :: FilePath
  , serverUrl :: ServerUrl
  , runtimeDirectory :: Maybe FilePath
  -- ^ ユーザ専用のtmpfs。ここに置いたファイルは、消し損ねてもディスクには書かれない。
  }
  deriving stock (Eq, Show)

-- | 環境変数を引く関数から設定を組み立てる。空は無いのと同じに扱う。
--
-- シークレットファイルかサーバのURLが無ければ`MissingVariable`を投げる。
configFrom :: (MonadThrow m) => (Text -> Maybe Text) -> m Config
configFrom lookupVariable =
  Config . convert
    <$> required lookupVariable "NIKS3_PUSH_NCAQ_SECRETS_FILE"
    <*> (ServerUrl <$> required lookupVariable "NIKS3_PUSH_NCAQ_SERVER_URL")
    <*> pure (convert <$> present lookupVariable "XDG_RUNTIME_DIR")
