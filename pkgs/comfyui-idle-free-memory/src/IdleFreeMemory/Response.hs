-- | ComfyUIの応答を解釈する。
--
-- HTTPには触れず、
-- デコード済みのJSONを受け取って必要な値だけを取り出す。
-- ComfyUIのAPIには型が無いので、
-- 引数は`Value`で受けて形をその場で確かめる。
--
-- `IdleFreeMemory.Run`から分けてあるのは、
-- ここがComfyUIのバージョンが上がると壊れる側だからである。
-- しかも壊れ方は「例外が出る」ではなく、
-- 「形が変わって静かに違う値を返す」になりやすい。
-- 純粋関数にしておけば、
-- 壊れた入力を並べたテストで分岐を固定できる。
module IdleFreeMemory.Response
  ( ResponseFailure (..)
  , queueRemaining
  , messageTimestamps
  , latestActivity
  ) where

import Himari

-- | 応答の形が想定と違った。
--
-- 呼び出し側はこれを捕まえてその周回を飛ばす。
data ResponseFailure
  = -- | `/prompt`がオブジェクトを返さなかった。
    PromptNotObject
  | -- | `/prompt`の応答に`exec_info`のオブジェクトが無かった。
    ExecInfoMissing
  | -- | `exec_info.queue_remaining`が有限の数値ではなかった。
    QueueRemainingNotNumber
  | -- | `/history`がオブジェクトを返さなかった。
    HistoryNotObject
  | -- | `/history`の件はあるのに時刻が1つも取れなかった。件数を持つ。
    HistoryWithoutTimestamps Int
  deriving stock (Eq, Show)

instance Exception ResponseFailure where
  displayException = \case
    PromptNotObject -> "/promptがオブジェクトを返しませんでした"
    ExecInfoMissing -> "/promptの応答にexec_infoがありませんでした"
    QueueRemainingNotNumber -> "/promptのqueue_remainingが数値ではありませんでした"
    HistoryNotObject -> "/historyがオブジェクトを返しませんでした"
    HistoryWithoutTimestamps count -> "/historyの" <> show count <> "件から時刻を1つも取れませんでした"

-- | JSONのオブジェクトなら中身を返す。
--
-- aesonの`KeyMap`にはlensの`Ixed`が無いので、
-- `Map`へ読み替えて`ix`で引けるようにする。
objectOf :: Value -> Maybe (Map Text Value)
objectOf value = case fromJSON value of
  Success object -> Just object
  Error _ -> Nothing

-- | JSONの配列なら中身を返す。
arrayOf :: Value -> Maybe [Value]
arrayOf value = case fromJSON value of
  Success array -> Just array
  Error _ -> Nothing

-- | JSONの数値で、しかも有限の場合だけ返す。
--
-- `Number`以外はここで弾く。
-- aesonの`Double`のデコーダは`null`をNaNとして受け入れるので、
-- それに任せずに先に構築子で絞る。
-- JSONの真偽値は数値とは別の構築子なので、
-- `true`が1として流れ込むことも無い。
--
-- 小数は受け入れる。
-- 上流が浮動小数点数で返すようになった時に、
-- 弾くと全件が飛んで`latestActivity`が失敗を返し、
-- 呼び出し側が周回を飛ばし続けて解放が二度と走らなくなる。
-- このプロセスが防ごうとしているOOMがそのまま再発するので、
-- 厳格に弾くより受け入れて動き続ける方が結果として良い。
-- 値はどのみち秒にするだけで、
-- キューの残数も`0 <`で比べるだけなので、小数でも壊れない。
--
-- 有限でない値は弾く。
-- JSONの数値は指数部を大きくすれば`Double`に収まらず無限大になり、
-- 無限大は`maximum`を占有して判定の意味を失わせる。
finiteNumber :: Value -> Maybe Double
finiteNumber = \case
  value@(Number _)
    | Success number <- fromJSON value
    , not (isNaN number || isInfinite number) ->
        Just number
  _ -> Nothing

-- | `Left`へ包む。
orFail :: e -> Maybe a -> Either e a
orFail failure = maybe (Left failure) Right

-- | `/prompt`の応答からキューに残っている数を取り出す。
--
-- 実行中のものも含まれるので、0でなければ何かしら動いている。
queueRemaining :: Value -> Either ResponseFailure Integer
queueRemaining response = do
  prompt <- orFail PromptNotObject (objectOf response)
  execInfo <- orFail ExecInfoMissing (prompt ^? ix "exec_info" >>= objectOf)
  remaining <- orFail QueueRemainingNotNumber (execInfo ^? ix "queue_remaining" >>= finiteNumber)
  -- 件数なので整数へ落とす。呼び出し側は`0 <`で比べるだけである。
  pure (truncate remaining)

-- | 履歴1件が持つ状態メッセージの時刻をミリ秒で集める。
--
-- 要素は`("execution_start", {...})`のタプルがJSONの配列になったものである。
-- 形が違うものは黙って飛ばす。
-- ここで欲しいのは最後の活動時刻だけで、
-- 1件読めなくても他の件と次の周回で足りるためである。
messageTimestamps :: Value -> [Double]
messageTimestamps entry = fromMaybe [] do
  status <- objectOf entry >>= (^? ix "status") >>= objectOf
  messages <- status ^? ix "messages" >>= arrayOf
  pure (mapMaybe timestampOf messages)
 where
  timestampOf message = do
    payload <- arrayOf message >>= (^? ix 1) >>= objectOf
    payload ^? ix "timestamp" >>= finiteNumber

-- | `/history`の応答から最後の実行時刻を取り出す。
--
-- 一度も実行していない場合は`Nothing`を返す。
--
-- 件はあるのに時刻が1つも取れなかった場合は失敗にする。
-- `messageTimestamps`は形の合わないものを黙って飛ばすので、
-- ComfyUIが`status.messages`の形やキー名を変えると全件が飛ばされる。
-- ここで`Nothing`を返すと呼び出し側は「一度も実行していない」とみなし、
-- 自分の観測だけでアイドルを判定する状態へ静かに退行する。
-- それはこのプロセスが避けようとしている、
-- 生成の直後に降ろす動作そのものである。
-- 件が0件の場合と区別して、上流の変化に気付けるようにする。
--
-- `/history?max_items=1`は`offset`の既定値の-1と組み合わさって、
-- `len(history) - max_items`がoffsetになるため新しい方の1件を返す。
latestActivity :: Value -> Either ResponseFailure (Maybe UTCTime)
latestActivity response = do
  entries <- orFail HistoryNotObject (objectOf response)
  case maximumMay (concatMap messageTimestamps entries) of
    Just milliseconds -> Right (Just (posixSecondsToUTCTime (realToFrac (milliseconds / 1000))))
    Nothing
      | null entries -> Right Nothing
      | otherwise -> Left (HistoryWithoutTimestamps (length entries))
