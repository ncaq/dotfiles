-- | アイドルかどうかの判定と、解放を要求するかどうかの決定。
--
-- 時刻は引数で受け取り、
-- 時計にも環境変数にもHTTPにも触れない。
-- 1周回分の遷移を1つの関数にまとめてあるので、
-- `IdleFreeMemory.Run`のループを回さずに順序と境界をテストで固定できる。
--
-- ここが一番壊れやすい。
-- 「確認と確認の隙間に終わった生成を拾い直す」
-- 「解放済みなら同じ要求を投げ直さない」
-- 「しきい値を跨いだ最初の周回でだけ解放する」
-- の3つが同時に成り立っている必要があり、
-- どれか1つを崩しても実機では滅多に表面化しないためである。
module IdleFreeMemory.State
  ( IdleState (..)
  , Observation (..)
  , Decision (..)
  , nextState
  ) where

import Himari

-- | 周回をまたいで持ち越す状態。
data IdleState = IdleState
  { lastActivity :: UTCTime
  -- ^ ComfyUIが最後に動いていた時刻。
  , freed :: Bool
  -- ^ 解放を要求済みかどうか。
  -- 次の活動があるまで同じ要求を投げ続けないために持つ。
  }
  deriving stock (Eq, Show)

-- | 1周回で観測したもの。
data Observation = Observation
  { now :: UTCTime
  , busy :: Bool
  -- ^ キューに残りがあるかどうか。
  , latest :: Maybe UTCTime
  -- ^ ComfyUI自身が記録した最後の活動時刻。
  -- 一度も実行していない場合と、busyなので引かなかった場合は`Nothing`になる。
  }
  deriving stock (Eq, Show)

-- | 解放を要求するかどうか。
data Decision
  = Hold
  | RequestFree
  deriving stock (Eq, Show)

-- | 1周回分の遷移を行い、更新後の状態と解放を要求すべきかを返す。
--
-- 解放が成功したかどうかはHTTPの結果次第なので、
-- ここでは`freed`を立てない。
-- 立てるのは実際に要求が通った後の呼び出し側である。
-- 要求に失敗した周回でフラグだけ進めてしまうと、
-- 次の活動があるまで再試行できなくなる。
nextState
  :: NominalDiffTime
  -- ^ これだけ何もしていなければ解放する。
  -> Observation
  -> IdleState
  -> (IdleState, Decision)
nextState idleThreshold observation current
  | observation.busy = (IdleState{lastActivity = observation.now, freed = False}, Hold)
  | caughtUp.freed = (caughtUp, Hold)
  | diffUTCTime observation.now caughtUp.lastActivity < idleThreshold = (caughtUp, Hold)
  | otherwise = (caughtUp, RequestFree)
 where
  caughtUp = case observation.latest of
    -- 未来の時刻は現在時刻へ倒す。
    -- コンテナ内の時刻ずれや、
    -- 履歴を書ける立場が未来のタイムスタンプを1件でも記録した場合に、
    -- そのまま代入すると経過時間が負のままになる。
    -- しきい値を二度と超えられなくなって解放が永久に止まり、
    -- GPUを共有する他のサービスへ直接効いてしまう。
    --
    -- 無視せず倒すのは、
    -- 未来を指していても「新しい活動があった」ことは事実だからである。
    Just latest
      | let activity = min latest observation.now
      , current.lastActivity < activity ->
          -- 確認と確認の間に始まって終わった生成をここで拾う。
          IdleState{lastActivity = activity, freed = False}
    _ -> current
