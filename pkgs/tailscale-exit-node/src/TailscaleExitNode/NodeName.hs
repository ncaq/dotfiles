-- | tailnetのノードの名前。
module TailscaleExitNode.NodeName
  ( NodeName (..)
  , homeServer
  ) where

import Himari

newtype NodeName = NodeName Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | 自宅サーバ。
--
-- レイテンシを測る相手であり、外出先でexit nodeにする相手でもある。
homeServer :: NodeName
homeServer = "seminar"
