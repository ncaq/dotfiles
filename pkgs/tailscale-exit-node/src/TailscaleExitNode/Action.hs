-- | NetworkManagerがdispatcherスクリプトへ渡すアクション。
--
-- 第2引数として渡される。一覧は`man 8 NetworkManager-dispatcher`にある。
module TailscaleExitNode.Action
  ( Action (..)
  , parseAction
  , requestedAction
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

-- | dispatcherスクリプトとして受け取った引数から、アクションを読む。
--
-- 第1引数がインターフェース名、第2引数がアクションである。
-- 人が呼ぶコマンドではないので、引数の数が合わない時も失敗にはせず`Nothing`にする。
requestedAction :: [String] -> Maybe Action
requestedAction = \case
  [_interface, action] -> parseAction (convert action)
  _ -> Nothing
