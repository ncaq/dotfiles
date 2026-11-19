-- | テストで共有する、偽の`sops`とシークレットファイルとログの集め方。
module Fixture
  ( variables
  , runCapturing
  , recordingSops
  , failingSops
  , withSecretsFile
  ) where

import Himari
import NixCachePushNcaq.Failure (SecretsFailure (..))
import NixCachePushNcaq.SecretKey (SecretKey)
import NixCachePushNcaq.Sops (Sops (..))

-- | 連想リストを、環境変数を引く関数にする。
variables :: [(Text, Text)] -> Text -> Maybe Text
variables = flip lookup

-- | ログを端末へ出さずに集めて、結果と共に返す。
runCapturing :: (MonadIO m) => Himari SimpleEnv a -> m (Either ExitCode a, [Text])
runCapturing action = do
  logs <- newIORef []
  result <-
    runSimpleEnvWith
      (\_ _ _ message -> modifyIORef' logs (<> [convert (fromLogStr message)]))
      (try action)
  (result,) <$> readIORef logs

-- | 呼び出しを記録して、決まったトークンを復号する偽の`sops`。
recordingSops :: (MonadIO m) => IORef [(SecretKey, FilePath)] -> Sops m
recordingSops calls =
  Sops{extract = \key path -> "token-example" <$ modifyIORef' calls (<> [(key, path)])}

-- | 復号に失敗する偽の`sops`。
failingSops :: (MonadThrow m) => Sops m
failingSops = Sops{extract = \_ path -> throwM (DecryptFailed path (ExitFailure 128))}

-- | 一時ディレクトリにシークレットファイルを置いて、そのパスを渡す。
withSecretsFile :: (MonadUnliftIO m) => (FilePath -> m a) -> m a
withSecretsFile action =
  withSystemTempDirectory "nix-cache-push-ncaq-test" \directory -> do
    let path = directory </> "secrets.yaml"
    liftIO (writeFile path "")
    action path
