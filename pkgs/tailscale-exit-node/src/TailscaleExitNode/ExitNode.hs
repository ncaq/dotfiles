-- | exit nodeを使うかどうかの決定。
--
-- 外出時はexit nodeを自宅サーバにする。
-- ただし自宅サーバと同じローカルネットワークにいる場合は、
-- 経由しても遠回りになるだけなので通常の通信を行う。
--
-- ローカルネットワークにいるかどうかは、自宅サーバへのレイテンシで判定する。
-- ローカルネットワークなら`0s`か数ms、外部なら数10ms以上になる。
-- 差し迫ったセキュリティ要件があるわけではないので、判定はこの程度の雑さで構わない。
module TailscaleExitNode.ExitNode
  ( ExitNode (..)
  , localThreshold
  , chooseExitNode
  , setArguments
  ) where

import Himari
import TailscaleExitNode.NodeName (NodeName (..))

data ExitNode
  = -- | exit nodeを使わずに直接通信する。
    Direct
  | -- | 指定のノードをexit nodeにする。
    Via NodeName
  deriving stock (Eq, Show)

-- | レイテンシがこれ以下ならローカルネットワークにいるとみなす。
localThreshold :: NominalDiffTime
localThreshold = 0.01

-- | 自宅サーバへのレイテンシから、exit nodeを決める。
--
-- レイテンシを測れなかった時は外部にいるとみなす。
-- 外にいるのに直接通信するより、家にいるのに経由する方が害が小さい。
chooseExitNode :: NodeName -> Maybe NominalDiffTime -> ExitNode
chooseExitNode home = \case
  Just latency | latency <= localThreshold -> Direct
  _ -> Via home

-- | exit nodeを設定する`tailscale`の引数。
setArguments :: ExitNode -> [String]
setArguments = \case
  Direct -> ["set", "--exit-node="]
  Via (NodeName name) -> ["set", "--exit-node=" <> convert name]
