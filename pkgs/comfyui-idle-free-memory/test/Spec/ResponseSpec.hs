-- | 応答の解釈のテスト。
--
-- 正常系より異常系が本体である。
-- ComfyUIのAPIには型が無く、
-- バージョンが上がって形が変わった時に、
-- 例外ではなく静かに違う値が返ることを防ぐために書いている。
module Spec.ResponseSpec (tests) where

import Himari
import IdleFreeMemory.Response
import Test.Sandwich

-- | キーが1つだけのJSONのオブジェクト。
singleton :: Text -> Value -> Value
singleton key value = toJSON (mempty & at key ?~ value :: Map Text Value)

-- | 履歴1件を、指定した時刻のメッセージで組み立てる。
entryOf :: [Value] -> Value
entryOf timestamps = singleton "status" (singleton "messages" (toJSON messages))
 where
  messages = [toJSON [String "execution_start", singleton "timestamp" t] | t <- timestamps]

-- | `/history?max_items=1`の応答を、`entryOf`の1件で組み立てる。
history :: [Value] -> Value
history = singleton "8f0e" . entryOf

brokenQueueResponses :: [(String, Value, ResponseFailure)]
brokenQueueResponses =
  [ ("オブジェクトですらない", [aesonQQ|[]|], PromptNotObject)
  , ("exec_infoが無い", [aesonQQ|{}|], ExecInfoMissing)
  , ("exec_infoがオブジェクトではない", [aesonQQ|{"exec_info": 1}|], ExecInfoMissing)
  , ("queue_remainingが無い", [aesonQQ|{"exec_info": {}}|], QueueRemainingNotNumber)
  ,
    ( "queue_remainingが文字列"
    , [aesonQQ|{"exec_info": {"queue_remaining": "3"}}|]
    , QueueRemainingNotNumber
    )
  , -- aesonの`Double`のデコーダは`null`をNaNとして受け入れるので、通さないことを固定する。

    ( "queue_remainingがnull"
    , [aesonQQ|{"exec_info": {"queue_remaining": null}}|]
    , QueueRemainingNotNumber
    )
  , -- 通すと`0 < 1`が成立して常時busy扱いになり、解放が永久に止まる。

    ( "queue_remainingが真偽値"
    , [aesonQQ|{"exec_info": {"queue_remaining": true}}|]
    , QueueRemainingNotNumber
    )
  ,
    ( "queue_remainingが偽"
    , [aesonQQ|{"exec_info": {"queue_remaining": false}}|]
    , QueueRemainingNotNumber
    )
  ]

brokenHistoryEntries :: [(String, Value)]
brokenHistoryEntries =
  [ ("件がオブジェクトではない", [aesonQQ|[]|])
  , ("statusが無い", [aesonQQ|{}|])
  , ("statusがオブジェクトではない", [aesonQQ|{"status": 1}|])
  , ("messagesが無い", [aesonQQ|{"status": {}}|])
  , ("messagesが配列ではない", [aesonQQ|{"status": {"messages": {}}}|])
  , ("要素が配列ではない", [aesonQQ|{"status": {"messages": [1]}}|])
  , ("要素が1つしかなくデータが無い", [aesonQQ|{"status": {"messages": [["execution_start"]]}}|])
  , ("データがオブジェクトではない", [aesonQQ|{"status": {"messages": [["execution_start", 1]]}}|])
  , ("timestampが無い", [aesonQQ|{"status": {"messages": [["execution_start", {}]]}}|])
  ,
    ( "timestampが文字列"
    , [aesonQQ|{"status": {"messages": [["execution_start", {"timestamp": "1000"}]]}}|]
    )
  , -- 通すと`true`が1ミリ秒の時刻として扱われる。

    ( "timestampが真偽値"
    , [aesonQQ|{"status": {"messages": [["execution_start", {"timestamp": true}]]}}|]
    )
  , -- 通すとNaNが`maximum`へ混ざる。

    ( "timestampがnull"
    , [aesonQQ|{"status": {"messages": [["execution_start", {"timestamp": null}]]}}|]
    )
  ]

tests :: TopSpec
tests = describe "Response" do
  describe "queueRemaining" do
    it "exec_infoから読む" do
      queueRemaining [aesonQQ|{"exec_info": {"queue_remaining": 3}}|] `shouldBe` Right 3
    it "0を受け入れる" do
      queueRemaining [aesonQQ|{"exec_info": {"queue_remaining": 0}}|] `shouldBe` Right 0
    it "小数を受け入れる" do
      -- 上流が数値を浮動小数点数で返すようになっても止まらないようにする。
      -- 弾くと毎周回が失敗になり、解放が二度と走らない。
      queueRemaining [aesonQQ|{"exec_info": {"queue_remaining": 3.0}}|] `shouldBe` Right 3
    for_ brokenQueueResponses \(caseName, response, failure) ->
      it ("壊れた形を弾く: " <> caseName) do
        queueRemaining response `shouldBe` Left failure
  describe "messageTimestamps" do
    it "全てのメッセージの時刻を集める" do
      messageTimestamps (entryOf [Number 1000, Number 2000]) `shouldBe` [1000, 2000]
    for_ brokenHistoryEntries \(caseName, entry) ->
      it ("壊れた形を飛ばす: " <> caseName) do
        messageTimestamps entry `shouldBe` []
    it "小数を受け入れる" do
      -- 弾くと全件が飛んで`latestActivity`が失敗を返し続ける。
      -- 症状は数分おきのログ1行だけで、防ごうとしていたOOMがそのまま再発する。
      messageTimestamps (entryOf [Number 1000.5]) `shouldBe` [1000.5]
    it "Doubleに収まらない数値を飛ばす" do
      -- 無限大は`maximum`を占有して判定の意味を失わせる。
      messageTimestamps (entryOf [Number 1e400, Number -1e400]) `shouldBe` []
  describe "latestActivity" do
    it "最も新しい時刻を秒にして返す" do
      latestActivity (history [Number 1000, Number 3000, Number 2000])
        `shouldBe` Right (Just (posixSecondsToUTCTime 3))
    it "空の履歴はNothing" do
      -- 一度も実行していない状態は異常ではない。
      latestActivity [aesonQQ|{}|] `shouldBe` Right Nothing
    it "オブジェクトでなければ失敗" do
      latestActivity [aesonQQ|[]|] `shouldBe` Left HistoryNotObject
    it "件があるのに時刻が無ければ失敗" do
      -- 件はあるのに時刻が1つも取れないのは、上流が形を変えた時の症状である。
      -- ここで黙ってNothingを返すと、
      -- 呼び出し側は「一度も実行していない」とみなして、
      -- 自分の観測だけでアイドルを判定する状態へ静かに退行する。
      -- それは生成の直後に降ろす動作そのものなので、失敗にして気付けるようにする。
      latestActivity (history [String "1000"]) `shouldBe` Left (HistoryWithoutTimestamps 1)
