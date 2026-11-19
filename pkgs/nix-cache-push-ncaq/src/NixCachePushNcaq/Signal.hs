-- | 終了を求めるシグナルの扱い。
module NixCachePushNcaq.Signal
  ( exitOnTermination
  ) where

import Control.Exception qualified
import Himari
import System.Posix.Signals (Handler (Catch), installHandler, sigHUP, sigTERM)

-- | SIGTERMとSIGHUPを、呼び出したスレッドへの`ExitFailure`の例外に変える。
--
-- GHCのランタイムが例外に変えるのはSIGINTだけで、
-- この2つは既定では後始末を実行せずにプロセスを終わらせる。
-- 一時ファイルを消す処理と子プロセスを止める処理を走らせるために、例外として届ける。
--
-- 終了コードはシェルの慣習に合わせて、128にシグナルの番号を足したものにする。
--
-- 投げるのにunliftioの`throwTo`は使わない。
-- 非同期例外の型で包まれて、ランタイムが終了コードとして扱わなくなる。
exitOnTermination :: (MonadIO m) => m ()
exitOnTermination = liftIO do
  thread <- myThreadId
  for_ [sigTERM, sigHUP] \signal ->
    installHandler
      signal
      (Catch (Control.Exception.throwTo thread (ExitFailure (128 + fromIntegral signal))))
      Nothing
