-- | 終了を求めるシグナルの扱いのテスト。
--
-- テストのプロセス自身へ実際にシグナルを送って確かめる。
module Spec.SignalSpec (tests) where

import Himari
import NixCachePushNcaq.Niks3.TokenFile (withTokenFile)
import NixCachePushNcaq.Signal (withTerminationAsExit)
import System.Posix.Signals (Signal, raiseSignal, sigHUP, sigTERM)
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
