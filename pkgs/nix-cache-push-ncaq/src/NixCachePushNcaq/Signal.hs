-- | 終了を求めるシグナルの扱い。
module NixCachePushNcaq.Signal
  ( withTerminationAsExit
  ) where

import Control.Exception qualified
import Himari hiding (Handler)
import System.Posix.Signals (Handler (Catch), Signal, installHandler, sigHUP, sigTERM)

-- | 処理の間だけ、SIGTERMとSIGHUPを呼び出したスレッドへの`ExitFailure`の例外に変える。
--
-- GHCのランタイムが例外に変えるのはSIGINTだけで、
-- この2つは既定では後始末を実行せずにプロセスを終わらせる。
-- 一時ファイルを消す処理と子プロセスを止める処理を走らせるために、例外として届ける。
--
-- 終了コードはシェルの慣習に合わせて、128にシグナルの番号を足したものにする。
-- 処理が終わったら前のハンドラへ戻す。
--
-- 投げるのにunliftioの`throwTo`は使わない。
-- 非同期例外の型で包まれて、ランタイムが終了コードとして扱わなくなる。
withTerminationAsExit :: (MonadUnliftIO m) => m a -> m a
withTerminationAsExit action = do
  thread <- myThreadId
  bracket (liftIO (traverse (install thread) signals)) (liftIO . restore) (const action)
 where
  signals = [sigTERM, sigHUP]
  install thread signal =
    (signal,)
      <$> installHandler
        signal
        (Catch (Control.Exception.throwTo thread (ExitFailure (128 + fromIntegral signal))))
        Nothing
  restore :: [(Signal, Handler)] -> IO ()
  restore = traverse_ \(signal, previous) -> installHandler signal previous Nothing
