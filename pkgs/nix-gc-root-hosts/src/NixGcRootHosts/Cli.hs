-- | 環境変数からの設定の読み取りと、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
module NixGcRootHosts.Cli
  ( run
  , runWith
  ) where

import Himari
import NixGcRootHosts.Config (configFrom)
import NixGcRootHosts.Nix (Nix, systemNix)
import NixGcRootHosts.Register (Outcome (..), register)

-- | プロセスの環境変数を設定として、実際の`nix`で実行する。引数は取らない。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run _ = do
  environment <- getEnvironment
  runWith systemNix (\name -> convert <$> lookup (convert name) environment)

-- | `nix`の呼び出しと環境変数を引く関数を受け取って実行する。
--
-- 設定が揃わない時と、登録できなかったrootがある時は、`ExitFailure 1`にする。
-- 理由はその場でログに出ている。
runWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => Nix m -> (Text -> Maybe Text) -> m ()
runWith nix lookupVariable = case configFrom lookupVariable of
  Left failure -> do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)
  Right config ->
    register nix config >>= \case
      AllRegistered -> pure ()
      SomeFailed _ -> throwM (ExitFailure 1)
