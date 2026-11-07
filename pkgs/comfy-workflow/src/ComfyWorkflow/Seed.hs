-- | ワークフローが振り直すと約束しているseedを見つける。
--
-- UIでseedの隣に並ぶ`fixed`や`randomize`はフロントエンドだけのウィジェットで、
-- `widgets_values`にはseedの値の次の位置に文字列として残る。
-- サーバはこれを読まないので、
-- APIから投げると書かれたseedがそのまま使われる。
-- 何も知らずに投げると同じ画像が出続ける。
--
-- 公式の`comfy run`も振り直さない。
-- 変換の時にこの文字列を捨てるだけである。
-- なのでここで約束を読み取って、
-- 投げる前に`comfy workflow set-slot`で値を書き換える。
--
-- `fixed`と書かれているものは触らない。
-- UIで意図して固定したものが、
-- APIから投げた時だけ動くのはおかしい。
module ComfyWorkflow.Seed
  ( seedTargets
  , controlWords
  ) where

import ComfyWorkflow.Parameter (seedWidgetNames)
import ComfyWorkflow.Slot (Slot (..))
import ComfyWorkflow.Workflow (Node (..))
import Himari

-- | フロントエンドがseedの次の位置へ書く、実行後の振る舞いの名前。
controlWords :: [Text]
controlWords = ["fixed", "increment", "decrement", "randomize"]

-- | 振り直すseedのアドレスを返す。
--
-- ノードごとに、
-- `widgets_values`の中で数値の直後に振る舞いの名前が続く箇所を順に拾い、
-- そのノードのseedのスロットへ順に対応させる。
-- どちらもウィジェットの並び順なので、
-- 位置合わせはこれで足りる。
seedTargets :: [Node] -> [Slot] -> [Text]
seedTargets nodes slots = concatMap targetsOf nodes
 where
  targetsOf node =
    let controls =
          [ control
          | (Number _, String control) <- zip node.widgetsValues (drop 1 node.widgetsValues)
          , control `elem` controlWords
          ]
        seedSlots =
          [ slot.address
          | slot <- slots
          , slot.instanceId == node.nodeId
          , slot.name `elem` seedWidgetNames
          ]
     in [address | (address, control) <- zip seedSlots controls, control /= "fixed"]
