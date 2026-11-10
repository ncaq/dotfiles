-- | 環境変数からの設定の読み取りと、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
module UserSettingsSync.Cli
  ( run
  ) where

import Himari
import UserSettingsSync.Config (Config (..), configFrom)
import UserSettingsSync.Declared (readDeclaration)
import UserSettingsSync.Failure (ApiFailure, ConfigFailure, DeclarationFailure, SyncFailure)
import UserSettingsSync.Sync (Environment (..), healthPolicy, sync)
import UserSettingsSync.Transport (httpTransport)

-- | プロセスの環境変数を設定として、実際のOpen WebUIに対して実行する。引数は取らない。
--
-- 想定している失敗は、理由をログに出して`ExitFailure 1`にする。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run _ =
  handle (report @ConfigFailure)
    . handle (report @DeclarationFailure)
    . handle (report @ApiFailure)
    . handle (report @SyncFailure)
    $ do
      environment <- getEnvironment
      config <-
        either throwM pure (configFrom (\name -> convert <$> lookup (convert name) environment))
      declaration <- readDeclaration config
      sync Environment{transport = httpTransport config.url, healthRetry = healthPolicy} declaration

-- | 想定している失敗を、ログに出して`ExitFailure 1`にする。
report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
report failure = do
  logErrorN (convert (displayException failure))
  throwM (ExitFailure 1)
