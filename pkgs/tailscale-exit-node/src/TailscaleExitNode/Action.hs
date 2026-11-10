-- | NetworkManagerがdispatcherスクリプトへ渡すアクション。
--
-- 第2引数として渡される。一覧は`man 8 NetworkManager-dispatcher`にある。
module TailscaleExitNode.Action
  ( Action (..)
  , parseAction
  ) where

import Himari

-- | exit nodeを選び直すきっかけになるアクション。
data Action = InterfaceUp
  deriving stock (Eq, Show)

-- | インターフェースが繋がった時だけを読む。
--
-- どのネットワークにいるかが変わるのは新しく繋がった時だけなので、
-- それ以外のアクションは`Nothing`にする。
parseAction :: Text -> Maybe Action
parseAction = \case
  "up" -> Just InterfaceUp
  _ -> Nothing
