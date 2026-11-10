-- | NetworkManagerがdispatcherスクリプトへ渡すアクション。
--
-- 第2引数として渡される。一覧は`man 8 NetworkManager-dispatcher`にある。
module WifiWiredExclusive.Action
  ( Action (..)
  , parseAction
  ) where

import Himari

-- | デバイスの接続状態が変化するアクション。
data Action
  = InterfaceUp
  | InterfaceDown
  deriving stock (Eq, Show)

-- | 接続状態が変化するアクションだけを読む。
--
-- `pre-up`や`dhcp4-change`や`connectivity-change`のような他のアクションでは、
-- 有線とWiFiのどちらを使うかは変わらないので`Nothing`にする。
parseAction :: Text -> Maybe Action
parseAction = \case
  "up" -> Just InterfaceUp
  "down" -> Just InterfaceDown
  _ -> Nothing
