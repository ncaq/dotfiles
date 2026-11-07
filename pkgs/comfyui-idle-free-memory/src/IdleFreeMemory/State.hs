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
  , initialState
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
  , seenHistory :: Maybe UTCTime
  -- ^ 最後に見た履歴の時刻を、現在時刻へ倒す前の値のまま持つ。
  -- 新しい活動かどうかはこれと比べて決める。
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

-- | ループへ入る前の状態を、起動時の現在時刻と履歴の時刻から決める。
--
-- 現在時刻から始めると、
-- このプロセスだけが再起動した時に困る。
-- ComfyUIが何時間も前から放置されていても、
-- 履歴の時刻は初期値より古いので拾い直されず、
-- 解放まで改めてしきい値の分だけ待つことになる。
-- 載ったままのモデルを取りこぼさないという意図が半分しか効かない。
--
-- 履歴が取れたらそれを使う。
-- 一度も実行していない場合と、
-- ComfyUIがまだ起動しきっていない場合は現在時刻へ倒す。
-- その場合に待つ時間は、
-- どのみち何も載っていないか、これから載るところなので惜しくない。
--
-- 未解放から始める。
-- 通常はコンテナが起きた直後で何も載っていないので、
-- 最初の1回だけ何も降ろさない要求が飛ぶことになるが、
-- 載っていなければ`unload_all_models`は何もしないので害は無い。
-- そのかわり、このプロセスだけが再起動した場合に、
-- 載ったままのモデルを取りこぼさずに済む。
initialState :: UTCTime -> Maybe UTCTime -> IdleState
initialState now latest =
  IdleState
    { -- 未来の時刻は`nextState`と同じく現在時刻へ倒す。
      lastActivity = maybe now (min now) latest
    , freed = False
    , -- 起動時に見た履歴を次の周回で新しい活動として数え直さないように、倒す前の値で持つ。
      seenHistory = latest
    }

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
  | observation.busy = (current{lastActivity = observation.now, freed = False}, Hold)
  | caughtUp.freed = (caughtUp, Hold)
  | diffUTCTime observation.now caughtUp.lastActivity < idleThreshold = (caughtUp, Hold)
  | otherwise = (caughtUp, RequestFree)
 where
  caughtUp = case observation.latest of
    -- 新しい活動かどうかは、倒す前の履歴の時刻同士で比べる。
    -- 倒した後の時刻を`lastActivity`と比べると、
    -- 同じ未来の時刻が毎周回`now`へ倒されて新しく見え続け、
    -- 時計がその未来の時刻に追いつくまで解放されなくなる。
    Just latest
      | all (< latest) current.seenHistory ->
          -- 確認と確認の間に始まって終わった生成をここで拾う。
          IdleState
            { -- 未来の時刻は現在時刻へ倒す。
              -- コンテナ内の時刻ずれや、
              -- 履歴を書ける立場が未来のタイムスタンプを1件でも記録した場合に、
              -- そのまま代入すると経過時間が負のままになる。
              -- 無視せず倒すのは、
              -- 未来を指していても「新しい活動があった」ことは事実だからである。
              --
              -- busyの間に進めた時刻より古い履歴で巻き戻さない。
              lastActivity = max current.lastActivity (min latest observation.now)
            , freed = False
            , seenHistory = Just latest
            }
    _ -> current
