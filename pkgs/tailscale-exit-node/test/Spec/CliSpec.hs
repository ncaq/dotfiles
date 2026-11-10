-- | dispatcherとして呼ばれた時の実行のテスト。
--
-- `tailscale`は記録するだけの偽物に差し替える。
module Spec.CliSpec (tests) where

import Himari
import TailscaleExitNode.Cli (runWith)
import TailscaleExitNode.ExitNode (ExitNode (..))
import TailscaleExitNode.NodeName (NodeName)
import TailscaleExitNode.Tailscale (Tailscale (..))
import Test.Sandwich

-- | 偽の`tailscale`への呼び出しの記録。
data Call
  = Ready
  | Ping NodeName
  | SetExitNode ExitNode
  deriving stock (Eq, Show)

-- | 実行して、偽の`tailscale`への呼び出しを順に返す。
--
-- 準備完了の問い合わせへ順に返す答えと、pingの出力を受け取る。
-- 答えを使い切った後の問い合わせには準備完了と答える。
called :: (MonadIO m) => [Bool] -> Text -> [String] -> m [Call]
called readiness pingOutput argv = do
  calls <- newIORef []
  answers <- newIORef readiness
  let record call = modifyIORef' calls (<> [call])
      tailscale =
        Tailscale
          { ready = do
              record Ready
              atomicModifyIORef' answers \case
                [] -> ([], True)
                answer : rest -> (rest, answer)
          , ping = \node -> pingOutput <$ record (Ping node)
          , setExitNode = record . SetExitNode
          }
  -- 待たずに最大3回まで問い合わせ直す。
  runSimpleNoLogEnv (runWith (limitRetries 3) tailscale argv)
  readIORef calls

localPong :: Text
localPong = "pong from seminar (100.82.4.93) via 192.168.10.88:41641 in 4ms"

externalPong :: Text
externalPong = "pong from seminar (100.82.4.93) via DERP(tok) in 38ms"

tests :: TopSpec
tests = describe "runWith" do
  it "ローカルネットワークならexit nodeを外す" do
    called [True] localPong ["wlp1s0", "up"]
      >>= (`shouldBe` [Ready, Ping "seminar", SetExitNode Direct])
  it "外部のネットワークなら自宅サーバをexit nodeにする" do
    called [True] externalPong ["wlp1s0", "up"]
      >>= (`shouldBe` [Ready, Ping "seminar", SetExitNode (Via "seminar")])
  it "pingが届かなければ外部とみなす" do
    called [True] "ping \"seminar\" timed out" ["wlp1s0", "up"]
      >>= (`shouldBe` [Ready, Ping "seminar", SetExitNode (Via "seminar")])
  it "tailscaledが応答するまで待ってからpingする" do
    called [False, False, True] localPong ["wlp1s0", "up"]
      >>= (`shouldBe` [Ready, Ready, Ready, Ping "seminar", SetExitNode Direct])
  it "待っても応答しなければ、そのまま進んで外部とみなす" do
    called (replicate 10 False) "failed to connect to local tailscaled" ["wlp1s0", "up"]
      >>= (`shouldBe` [Ready, Ready, Ready, Ready, Ping "seminar", SetExitNode (Via "seminar")])
  for_ [["wlp1s0", "down"], ["wlp1s0", "pre-up"], ["wlp1s0"], []] \argv ->
    it ("引数が" <> show argv <> "なら何もしない") do
      called [True] localPong argv >>= (`shouldBe` [])
