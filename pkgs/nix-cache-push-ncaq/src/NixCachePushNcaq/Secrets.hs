-- | シークレットファイルからの認証トークンの取り出し。
module NixCachePushNcaq.Secrets
  ( authTokenFrom
  ) where

import Himari
import NixCachePushNcaq.AuthToken (AuthToken)
import NixCachePushNcaq.Failure (SecretsFailure (..))
import NixCachePushNcaq.SecretKey (SecretKey)
import NixCachePushNcaq.Sops (Sops (..))

-- | シークレットファイルから、キーの指す認証トークンを復号する。
--
-- シークレットファイルが無ければ、`sops`を呼ぶ前に`SecretsFileNotFound`を投げる。
-- `sops`の説明より先に、どのファイルを探したかを知らせる。
authTokenFrom :: (MonadIO m, MonadThrow m) => Sops m -> SecretKey -> FilePath -> m AuthToken
authTokenFrom sops key path = do
  exists <- doesFileExist path
  unless exists (throwM (SecretsFileNotFound path))
  sops.extract key path
