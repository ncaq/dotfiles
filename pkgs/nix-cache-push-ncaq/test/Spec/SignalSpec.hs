-- | 終了を求めるシグナルの扱いのテスト。
--
-- テストのプロセス自身へ実際にシグナルを送って確かめる。
module Spec.SignalSpec (tests) where

import Himari hiding (Handler)
import NixCachePushNcaq.Niks3.TokenFile (withTokenFile)
import NixCachePushNcaq.Signal (withTerminationAsExit)
import System.Posix.Signals
  ( Handler (Catch)
  , Signal
  , installHandler
  , raiseSignal
  , sigHUP
  , sigTERM
  )
import Test.Sandwich

-- | トークンの一時ファイルを開いている間にシグナルを受けて、どう終わるかを返す。
--
-- シグナルは別のスレッドで例外に変わって届くので、届くまで待つ。
-- 届かなければ待ち切って例外にならずに終わり、テストが失敗する。
terminatedWhileHolding :: (MonadUnliftIO m) => Signal -> m (Either ExitCode (), [FilePath])
terminatedWhileHolding signal =
  withSystemTempDirectory "nix-cache-push-ncaq-test" \directory -> do
    result <-
      try
        ( withTerminationAsExit
            ( withTokenFile directory "token-example" \_ -> liftIO do
                raiseSignal signal
                threadDelay 10_000_000
            )
        )
    (result,) <$> listDirectory directory

tests :: TopSpec
tests = describe "withTerminationAsExit" do
  it "SIGTERMで143として終わり、トークンのファイルを消す" do
    terminatedWhileHolding sigTERM >>= (`shouldBe` (Left (ExitFailure 143), []))
  it "SIGHUPで129として終わり、トークンのファイルを消す" do
    terminatedWhileHolding sigHUP >>= (`shouldBe` (Left (ExitFailure 129), []))
  it "抜けた後は前のハンドラへ戻す" do
    -- 外側に自前のハンドラを入れておき、抜けた後のシグナルがそこへ届くことを確かめる。
    -- 戻し損ねていると、例外に変えるハンドラが残っていて、このテスト自身が143で終わる。
    received <- newEmptyMVar
    bracket
      (liftIO (installHandler sigTERM (Catch (putMVar received ())) Nothing))
      (\previous -> liftIO (installHandler sigTERM previous Nothing))
      \_ -> do
        withTerminationAsExit (pure ())
        liftIO (raiseSignal sigTERM)
        timeout 5_000_000 (takeMVar received) >>= (`shouldBe` Just ())
