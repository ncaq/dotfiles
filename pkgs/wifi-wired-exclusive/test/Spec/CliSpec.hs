-- | dispatcherとして呼ばれた時の実行のテスト。
--
-- `nmcli`は記録するだけの偽物に差し替える。
module Spec.CliSpec (tests) where

import Data.Text (isInfixOf)
import Himari
import Test.Sandwich
import WifiWiredExclusive.Cli (runWith)
import WifiWiredExclusive.Nmcli (Nmcli (..))
import WifiWiredExclusive.Operation (Operation (..))

-- | 実行して、行われた操作と出たログを返す。
--
-- 一覧として返す出力と、操作ごとの終了コードを決める関数を受け取る。
executed
  :: (MonadIO m) => Text -> (Operation -> ExitCode) -> [String] -> m ([Operation], [Text])
executed devices exitCodeOf argv = do
  operations <- newIORef []
  logs <- newIORef []
  let nmcli =
        Nmcli
          { listDevices = pure devices
          , perform = \operation -> do
              modifyIORef' operations (<> [operation])
              pure (exitCodeOf operation)
          }
  runSimpleEnvWith
    (\_ _ _ message -> modifyIORef' logs (<> [convert (fromLogStr message)]))
    (runWith nmcli argv)
  (,) <$> readIORef operations <*> readIORef logs

succeeding :: Operation -> ExitCode
succeeding = const ExitSuccess

-- | 有線が無く、WiFiが切れている。
wirelessOnly :: Text
wirelessOnly = "enp9s0:ethernet:unavailable\nwlp8s0:wifi:disconnected\n"

tests :: TopSpec
tests = describe "runWith" do
  it "upで操作を順に行う" do
    executed wirelessOnly succeeding ["enp9s0", "up"]
      >>= (`shouldBe` ([EnableAutoconnect "wlp8s0", Connect "wlp8s0"], []))
  it "downでも操作を行う" do
    executed wirelessOnly succeeding ["enp9s0", "down"]
      >>= (`shouldBe` ([EnableAutoconnect "wlp8s0", Connect "wlp8s0"], []))
  it "有線が繋がっていればWiFiを切る" do
    executed "enp9s0:ethernet:connected\nwlp8s0:wifi:connected\n" succeeding ["enp9s0", "up"]
      >>= (`shouldBe` ([Disconnect "wlp8s0"], []))
  for_ [["enp9s0", "pre-up"], ["enp9s0", "dhcp4-change"], ["enp9s0"], []] \argv ->
    it ("引数が" <> show argv <> "なら何もしない") do
      executed wirelessOnly succeeding argv >>= (`shouldBe` ([], []))
  it "操作が失敗しても記録を残して残りの操作を続ける" do
    let exitCodeOf = \case
          EnableAutoconnect _ -> ExitFailure 10
          _ -> ExitSuccess
    (operations, logs) <- executed wirelessOnly exitCodeOf ["enp9s0", "up"]
    operations `shouldBe` [EnableAutoconnect "wlp8s0", Connect "wlp8s0"]
    length logs `shouldBe` 1
    filter (isInfixOf "終了コード10") logs `shouldBe` logs
