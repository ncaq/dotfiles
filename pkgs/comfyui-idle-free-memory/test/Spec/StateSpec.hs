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

-- | 最後の活動の時刻と、その時刻の履歴を見たところの状態。
idleAt :: NominalDiffTime -> Bool -> IdleState
idleAt lastActivity freed =
  IdleState{lastActivity = at' lastActivity, freed, seenHistory = Just (at' lastActivity)}

-- | 最後に見た履歴の時刻だけを差し替える。
seen :: NominalDiffTime -> IdleState -> IdleState
seen history state' = state'{seenHistory = Just (at' history)}

tests :: TopSpec
tests = describe "State" do
  it "busyなら時計を巻き戻す" do
    -- 実行中なら、履歴を見るまでもなく現在時刻が最後の活動になる。
    -- 履歴は引いていないので、最後に見た履歴の時刻は変えない。
    nextState idle (quiet 1000){busy = True} (idleAt 0 True)
      `shouldBe` (seen 0 (idleAt 1000 False), Hold)
  it "busyなら履歴を見ない" do
    -- busyなら履歴は結果に影響しない。
    -- 影響しないものを引かずに済ませられることを、呼び出し側の根拠として固定する。
    nextState idle (withHistory 1000 500){busy = True} (idleAt 0 True)
      `shouldBe` nextState idle (quiet 1000){busy = True} (idleAt 0 True)
  it "新しい履歴を拾い直す" do
    -- 確認と確認の間に始まって終わった生成を拾い直す経路。
    -- 拾ったら解放済みのフラグも戻す。
    nextState idle (withHistory 1000 900) (idleAt 100 True) `shouldBe` (idleAt 900 False, Hold)
  it "履歴をまだ見ていない状態から最初の活動を拾う" do
    -- 起動時に履歴が空だったか取れなかった後、
    -- 確認の合間に短い生成が1件終わった時がこれに当たる。
    nextState idle (withHistory 1000 900) (initialState (at' 500) Nothing)
      `shouldBe` (seen 900 (idleAt 900 False), Hold)
  it "古い時刻の件へ入れ替わっても時計は巻き戻さない" do
    -- 時計の巻き戻しや履歴の削除の時に起こる。
    -- 入れ替わりを活動として数えて解放済みを戻すので、
    -- しきい値を超えていれば解放の要求がもう1回飛ぶ。
    -- 最後の活動の時刻が過去へ戻ることは無い。
    nextState idle (withHistory 2000 100) (idleAt 900 True)
      `shouldBe` (seen 100 (idleAt 900 False), RequestFree)
  it "同じ時刻の履歴では解放済みのフラグを戻さない" do
    -- 実機ではこれが普段の状態である。
    -- 解放した後も`/history?max_items=1`は毎周回同じ最後の1件を返す。
    -- ここで戻すと、しきい値を超えている間ずっと毎周回`/free`を投げ続ける。
    nextState idle (withHistory 10000 900) (idleAt 900 True) `shouldBe` (idleAt 900 True, Hold)
  it "履歴が無ければ時計を動かさない" do
    nextState idle (quiet 1000) (idleAt 900 False) `shouldBe` (idleAt 900 False, Hold)
  it "未来の履歴は現在時刻へ倒す" do
    -- 履歴に未来の時刻が1件でも入ると、
    -- 素直に代入したら経過時間が負のままになり、
    -- しきい値を二度と超えられなくなって解放が永久に止まる。
    -- このプロセスはOllamaのCUDA OOMを防ぐための緩和策なので、
    -- 静かな無効化はGPUを共有する他のサービスへ直接効く。
    -- 最後に見た履歴の時刻は倒す前の値のまま持つ。
    nextState idle (withHistory 1000 99999) (idleAt 0 False)
      `shouldBe` (seen 99999 (idleAt 1000 False), Hold)
  it "未来の履歴でも解放済みのフラグは戻す" do
    -- 倒しても「新しい活動があった」ことは事実である。
    nextState idle (withHistory 1000 99999) (idleAt 0 True)
      `shouldBe` (seen 99999 (idleAt 1000 False), Hold)
  it "未来の履歴の後に普通の時刻の履歴が来たら活動として拾う" do
    -- `/history?max_items=1`が返すのは時刻が最大の件ではなく、最後に追加された件である。
    -- 未来の時刻より前の時刻で短い生成が終わっても、新しい活動として数えなければならない。
    -- 数えないと生成の直後に解放してしまう。
    nextState idle (withHistory 2000 1900) (seen 99999 (idleAt 1000 True))
      `shouldBe` (seen 1900 (idleAt 1900 False), Hold)
  it "busyの間に進めた時刻を古い履歴で巻き戻さない" do
    -- busyの周回は履歴を引かないので、
    -- 次の周回で初めて見る履歴が、busyで記録した時刻より古いことがある。
    nextState idle (withHistory 2000 1500) (seen 0 (idleAt 1800 False))
      `shouldBe` (seen 1500 (idleAt 1800 False), Hold)
  it "未来の履歴が残り続けても有限の周回で解放する" do
    -- 1周回だけ見れば倒すことで経過時間は負にならないが、
    -- 同じ未来の時刻を毎周回拾い直すと`lastActivity`が毎回`now`へ進み、
    -- 時計がその未来の時刻に追いつくまで解放されない。
    let step (current, _) now = nextState idle (withHistory now 99999) current
        decisions = snd <$> drop 1 (scanl step (idleAt 0 False, Hold) [1000, 1300 .. 2500])
    (RequestFree `elem` decisions) `shouldBe` True
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
  describe "initialState" do
    it "履歴が無ければ現在時刻から未解放で始める" do
      -- 一度も実行していない場合と、履歴を取れなかった場合の両方がここに来る。
      initialState (at' 1000) Nothing
        `shouldBe` IdleState{lastActivity = at' 1000, freed = False, seenHistory = Nothing}
    it "履歴があればその時刻から始める" do
      -- このプロセスだけが再起動した時に、しきい値の分を改めて待たないようにする。
      initialState (at' 1000) (Just (at' 400)) `shouldBe` idleAt 400 False
    it "未来の履歴は現在時刻へ倒し、見た時刻は倒す前の値で持つ" do
      initialState (at' 1000) (Just (at' 99999)) `shouldBe` seen 99999 (idleAt 1000 False)
    it "起動時に見た履歴は次の周回で新しい活動として数えない" do
      -- 数え直すと、起動時から未来を指していた履歴で解放が1周回分遅れる。
      nextState idle (withHistory 1600 99999) (initialState (at' 1000) (Just (at' 99999)))
        `shouldBe` (seen 99999 (idleAt 1000 False), RequestFree)
