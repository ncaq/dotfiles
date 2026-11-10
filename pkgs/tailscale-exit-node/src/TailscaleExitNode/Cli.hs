-- | コマンドライン引数の解釈と実行。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
--
-- NetworkManagerのdispatcherスクリプトとして、デバイスのイベントごとに呼ばれる。
-- 第1引数がインターフェース名、第2引数がアクションである。
module TailscaleExitNode.Cli
  ( run
  , runWith
  , Readiness (..)
  , readiness
  ) where

import Himari
import TailscaleExitNode.Action (parseAction)
import TailscaleExitNode.ExitNode (ExitNode (..), chooseExitNode)
import TailscaleExitNode.Latency (parsePingLatency)
import TailscaleExitNode.NodeName (homeServer)
import TailscaleExitNode.Tailscale (Tailscale (..), systemTailscale)

-- | 実際の`tailscale`で実行する。
run :: (MonadLogger m, MonadUnliftIO m) => [String] -> m ()
run = runWith readiness systemTailscale

-- | tailscaledの準備完了の待ち方。
data Readiness m = Readiness
  { policy :: RetryPolicyM m
  -- ^ 問い合わせ直す間隔と回数。
  , limit :: Int
  -- ^ 待ち全体の上限。マイクロ秒。
  }

-- | tailscaledの準備完了を1秒おきに、全体で最大30秒待つ。
--
-- systemdのサービスを介して待つと、dispatcherからの同期起動で依存が循環するので、
-- ここで待つ。
-- 相手は同じマシンのデーモンなので、間隔を広げていく必要は無い。
--
-- 回数の上限とは別に、全体の上限も持つ。
-- 回数の上限が数えるのは問い合わせの間の待ち時間だけなので、
-- tailscaledが接続を受け付けたまま応答しないと、1回の問い合わせが返らずに待ち続けてしまう。
-- dispatcherはスクリプトを順番に実行するので、ここで止まると他のスクリプトも待たされる。
readiness :: (Monad m) => Readiness m
readiness = Readiness{policy = constantDelay 1000000 <> limitRetries 30, limit = 30000000}

-- | 待ち方と`tailscale`の呼び出しを受け取って実行する。
--
-- インターフェースが繋がった時でなければ何もしない。
-- 人が呼ぶコマンドではないので、引数が足りない時も何もせず成功で終わる。
--
-- tailscaledが待っても応答しない時も、そのまま先へ進む。
-- pingが届かないので外部にいるとみなすことになる。
runWith
  :: (MonadLogger m, MonadUnliftIO m) => Readiness m -> Tailscale m -> [String] -> m ()
runWith waiting tailscale = \case
  [_interface, action] | isJust (parseAction (convert action)) -> do
    void . timeout waiting.limit $
      retrying waiting.policy (\_ isReady -> pure (not isReady)) (const tailscale.ready)
    latency <- parsePingLatency <$> tailscale.ping homeServer
    let exitNode = chooseExitNode homeServer latency
    logInfoN (describe latency exitNode)
    tailscale.setExitNode exitNode
  _ -> pure ()
 where
  describe latency exitNode =
    "自宅サーバへのレイテンシは"
      <> maybe "不明" (convert . show) latency
      <> case exitNode of
        Direct -> "なので、ローカルネットワークとみなしてexit nodeを外します"
        Via _ -> "なので、外部のネットワークとみなしてexit nodeを使います"
