-- | 環境変数からの設定の読み取りと、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
module CachixPushNcaq.Cli
  ( run
  , runWith
  ) where

import CachixPushNcaq.Config (configFrom)
import CachixPushNcaq.Failure (ConfigFailure, SecretsFailure)
import CachixPushNcaq.Push (pushWith)
import CachixPushNcaq.Tools (Tools, systemTools)
import Himari

-- | プロセスの環境変数を設定として、実際の`sops`と`cachix`で実行する。
--
-- 引数は解釈せず、全て`cachix push`へ渡す。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run args = do
  environment <- getEnvironment
  runWith systemTools (\name -> convert <$> lookup (convert name) environment) args

-- | コマンドの呼び出しと環境変数を引く関数を受け取って実行する。
--
-- 転送が失敗した時は、説明は`cachix`自身が既に出しているので、その終了コードをそのまま伝える。
-- 設定が揃わない時と、認証トークンを得られなかった時は、理由をログに出して`ExitFailure 1`にする。
runWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m)
  => Tools m
  -> (Text -> Maybe Text)
  -> [String]
  -> m ()
runWith tools lookupVariable args =
  handle (report @ConfigFailure) . handle (report @SecretsFailure) $ do
    config <- configFrom lookupVariable
    code <- pushWith tools config args
    unless (code == ExitSuccess) (throwM code)
 where
  report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
  report failure = do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)
