-- | dispatcherとして呼ばれた時の実行のテスト。
--
-- `tailscale`は記録するだけの偽物に差し替える。
module Spec.CliSpec (tests) where

import Himari
import TailscaleExitNode.Cli (Readiness (..), runWith)
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
called answers pingOutput argv = do
  remaining <- newIORef answers
  let answer =
        atomicModifyIORef' remaining \case
          [] -> ([], True)
          next : rest -> (rest, next)
  calledWith answer pingOutput argv

-- | 準備完了の問い合わせへの答え方を受け取って実行して、偽の`tailscale`への呼び出しを順に返す。
calledWith :: (MonadIO m) => IO Bool -> Text -> [String] -> m [Call]
calledWith answer pingOutput argv = do
  calls <- newIORef []
  let record call = modifyIORef' calls (<> [call])
      tailscale =
        Tailscale
          { ready = do
              record Ready
              liftIO answer
          , ping = \node -> pingOutput <$ record (Ping node)
          , setExitNode = record . SetExitNode
          }
  -- 待たずに最大3回まで問い合わせ直す。全体の上限は50ミリ秒にする。
  runSimpleNoLogEnv (runWith Readiness{policy = limitRetries 3, limit = 50000} tailscale argv)
  readIORef calls

localPong :: Text
localPong = "pong from seminar (fd7a:115c:a1e0::b934:6c4a) via [2001:db8::1]:41641 in 4ms"

externalPong :: Text
externalPong = "pong from seminar (fd7a:115c:a1e0::b934:6c4a) via DERP(tok) in 38ms"

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
  it "問い合わせが返らなくても、全体の上限で打ち切って進む" do
    -- tailscaledが接続を受け付けたまま応答しない時がこれに当たる。
    calledWith (forever (threadDelay 1000000)) "failed to connect" ["wlp1s0", "up"]
      >>= (`shouldBe` [Ready, Ping "seminar", SetExitNode (Via "seminar")])
  for_ [["wlp1s0", "down"], ["wlp1s0", "pre-up"], ["wlp1s0"], []] \argv ->
    it ("引数が" <> show argv <> "なら何もしない") do
      called [True] localPong argv >>= (`shouldBe` [])
