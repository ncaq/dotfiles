-- | 遷移のテスト。
--
-- 実機で確かめられるのは1周回に1本の経路だけで、
-- しかも1周回は数分かかる。
-- 順序と境界はここで固定する。
module Spec.StateSpec (tests) where

import Himari
import IdleFreeMemory.State
import Test.Sandwich

-- | しきい値。テストの中で意味を持つのは大小関係だけなので短くする。
idle :: NominalDiffTime
idle = 600

-- | UNIX時刻の秒から時刻を作る。
at' :: NominalDiffTime -> UTCTime
at' = posixSecondsToUTCTime

-- | busyではなく、履歴も無い観測。
quiet :: NominalDiffTime -> Observation
quiet now = Observation{now = at' now, busy = False, latest = Nothing}

-- | busyではなく、履歴の時刻だけがある観測。
withHistory :: NominalDiffTime -> NominalDiffTime -> Observation
withHistory now latest = (quiet now){latest = Just (at' latest)}

idleAt :: NominalDiffTime -> Bool -> IdleState
idleAt lastActivity freed = IdleState{lastActivity = at' lastActivity, freed}

tests :: TopSpec
tests = describe "State" do
  it "busyなら時計を巻き戻す" do
    -- 実行中なら、履歴を見るまでもなく現在時刻が最後の活動になる。
    nextState idle (quiet 1000){busy = True} (idleAt 0 True) `shouldBe` (idleAt 1000 False, Hold)
  it "busyなら履歴を見ない" do
    -- busyなら履歴は結果に影響しない。
    -- 影響しないものを引かずに済ませられることを、呼び出し側の根拠として固定する。
    nextState idle (withHistory 1000 500){busy = True} (idleAt 0 True)
      `shouldBe` nextState idle (quiet 1000){busy = True} (idleAt 0 True)
  it "新しい履歴を拾い直す" do
    -- 確認と確認の間に始まって終わった生成を拾い直す経路。
    -- 拾ったら解放済みのフラグも戻す。
    nextState idle (withHistory 1000 900) (idleAt 100 True) `shouldBe` (idleAt 900 False, Hold)
  it "古い履歴では時計を動かさない" do
    nextState idle (withHistory 2000 100) (idleAt 900 True) `shouldBe` (idleAt 900 True, Hold)
  it "履歴が無ければ時計を動かさない" do
    nextState idle (quiet 1000) (idleAt 900 False) `shouldBe` (idleAt 900 False, Hold)
  it "未来の履歴は現在時刻へ倒す" do
    -- 履歴に未来の時刻が1件でも入ると、
    -- 素直に代入したら経過時間が負のままになり、
    -- しきい値を二度と超えられなくなって解放が永久に止まる。
    -- このプロセスはOllamaのCUDA OOMを防ぐための緩和策なので、
    -- 静かな無効化はGPUを共有する他のサービスへ直接効く。
    nextState idle (withHistory 1000 99999) (idleAt 0 False) `shouldBe` (idleAt 1000 False, Hold)
  it "未来の履歴でも解放済みのフラグは戻す" do
    -- 倒しても「新しい活動があった」ことは事実である。
    nextState idle (withHistory 1000 99999) (idleAt 0 True) `shouldBe` (idleAt 1000 False, Hold)
  it "解放済みなら投げ直さない" do
    -- しきい値を超え続けている間、同じ要求を投げ続けないことを固定する。
    nextState idle (quiet 10000) (idleAt 0 True) `shouldBe` (idleAt 0 True, Hold)
  it "しきい値の手前では待つ" do
    nextState idle (quiet (1000 + idle - 1)) (idleAt 1000 False)
      `shouldBe` (idleAt 1000 False, Hold)
  it "しきい値ちょうどで解放する" do
    nextState idle (quiet (1000 + idle)) (idleAt 1000 False)
      `shouldBe` (idleAt 1000 False, RequestFree)
  it "解放済みのフラグは遷移では立てない" do
    -- 解放が成功したかはHTTPの結果次第なので、ここでは立てない。
    -- 立ててしまうと、要求に失敗した周回で次の活動まで再試行できなくなる。
    nextState idle (quiet 10000) (idleAt 1000 False) `shouldBe` (idleAt 1000 False, RequestFree)
