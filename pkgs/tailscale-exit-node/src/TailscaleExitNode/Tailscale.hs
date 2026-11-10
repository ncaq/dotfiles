-- | `tailscale`の呼び出し。
--
-- 呼び出しを値として持つのは、テストで実際のtailnetを触らずに済ませるためである。
module TailscaleExitNode.Tailscale
  ( Tailscale (..)
  , systemTailscale
  ) where

import Himari
import TailscaleExitNode.ExitNode (ExitNode, setArguments)
import TailscaleExitNode.NodeName (NodeName (..))

data Tailscale m = Tailscale
  { ready :: m Bool
  -- ^ tailscaledが応答するか。
  , ping :: NodeName -> m Text
  -- ^ ノードへ1回pingして、出力を返す。届かなくても失敗にはしない。
  , setExitNode :: ExitNode -> m ()
  -- ^ exit nodeを設定する。失敗したら例外を投げる。
  }

-- | PATHにある`tailscale`を呼ぶ。
systemTailscale :: (MonadIO m) => Tailscale m
systemTailscale =
  Tailscale
    { ready = (== ExitSuccess) <$> runProcess (quiet (tailscale ["status", "--peers=false"]))
    , ping = \(NodeName name) ->
        -- 届かなかった理由は標準エラー出力へ出るので、両方をまとめて受け取る。
        convert . snd <$> readProcessInterleaved (tailscale ["ping", "-c", "1", convert name])
    , setExitNode = runProcess_ . tailscale . setArguments
    }
 where
  tailscale = proc "tailscale"
  -- 準備ができていない間のエラーを、問い合わせのたびに端末へ出さない。
  quiet = setStdout nullStream . setStderr nullStream
