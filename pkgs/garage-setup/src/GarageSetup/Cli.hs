-- | 環境変数からの設定の読み取りと、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
module GarageSetup.Cli
  ( run
  , report
  ) where

import GarageSetup.AdminToken (readAdminToken)
import GarageSetup.Config (Config (..), configFrom)
import GarageSetup.Failure (ApiFailure, ConfigFailure)
import GarageSetup.KeyFile (giveTo, writeSecretFile)
import GarageSetup.Setup (Environment (..), healthPolicy, setup)
import GarageSetup.Transport (httpTransport)
import Himari

-- | プロセスの環境変数を設定として、実際のGarageに対して実行する。引数は取らない。
--
-- 設定が揃わない時と、Admin APIの応答を使えなかった時は、理由をログに出して`ExitFailure 1`にする。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run _ = handle (report @ConfigFailure) . handle (report @ApiFailure) $ do
  environment <- getEnvironment
  config <-
    either throwM pure (configFrom (\name -> convert <$> lookup (convert name) environment))
  token <- readAdminToken config.adminTokenFile
  setup
    Environment
      { transport = httpTransport config.api token
      , healthRetry = healthPolicy
      , writeKeyFile = \file content -> do
          let path = config.runtimeDirectory </> file
          writeSecretFile path content
          giveTo config.name path
      }
    config.name

-- | 想定している失敗を、ログに出して`ExitFailure 1`にする。
report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
report failure = do
  logErrorN (convert (displayException failure))
  throwM (ExitFailure 1)
