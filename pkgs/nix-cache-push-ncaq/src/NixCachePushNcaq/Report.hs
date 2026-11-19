-- | 結果の終了コードへの変換。
module NixCachePushNcaq.Report
  ( finish
  ) where

import Himari
import NixCachePushNcaq.Failure (ConfigFailure, SecretsFailure)

-- | 転送までの処理を実行して、結果をプロセスの終了の仕方にする。
--
-- 転送が失敗した時は、説明は転送するコマンド自身が既に出しているので、その終了コードをそのまま伝える。
-- 設定が揃わない時と、認証トークンを得られなかった時は、理由をログに出して`ExitFailure 1`にする。
finish :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => m ExitCode -> m ()
finish action =
  handle (report @ConfigFailure) . handle (report @SecretsFailure) $ do
    code <- action
    unless (code == ExitSuccess) (throwM code)
 where
  report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
  report failure = do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)
