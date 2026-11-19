-- | 認証トークンの復号と、キャッシュへの転送。
module CachixPushNcaq.Push
  ( pushWith
  ) where

import CachixPushNcaq.Config (Config (..))
import CachixPushNcaq.Failure (SecretsFailure (..))
import CachixPushNcaq.Tools (Tools (..))
import Himari

-- | シークレットファイルから認証トークンを復号して、キャッシュへ転送する。
--
-- 引数はそのまま`cachix push <cache>`の後ろへ渡す。
-- 引数が無ければ`cachix`が標準入力からstoreパスの一覧を読む。
--
-- シークレットファイルが無ければ、`sops`を呼ぶ前に`SecretsFileNotFound`を投げる。
-- 転送の終了コードはそのまま返す。
pushWith :: (MonadIO m, MonadThrow m) => Tools m -> Config -> [String] -> m ExitCode
pushWith tools config args = do
  exists <- doesFileExist config.secretsFile
  unless exists (throwM (SecretsFileNotFound config.secretsFile))
  token <- tools.decrypt config.secretsFile
  tools.push token config.cacheName args
