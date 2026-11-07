-- | ComfyUIがアイドルになったらメモリを解放させる常駐プロセス。
--
-- ComfyUIはsmart memoryで実行後も重みをVRAMへ保持し続ける。
-- 同じモデルを連続で使う分には正しい挙動だが、
-- 使い終わって放置している間も抱えたままになる。
-- bulletではOllamaが同じGPUを使うので、
-- 抱えられたままだと汎用モデルがCUDAのOOMで載らない。
--
-- ComfyUI本体にこれを時間で解く仕組みは無い。
-- 0.33.1の`comfy/cli_args.py`には該当する引数が無く、
-- `--disable-smart-memory`は実行のたびに降ろす別物である。
-- 上流でも「作業セッションの後にVRAMが解放されない」という要望が挙がったまま実装されていない。
-- <https://github.com/Comfy-Org/ComfyUI/issues/3192>
--
-- コンテナごと止めれば全て解決するが、それはできない。
-- ComfyUIはSQLiteへ保存した状態の一部をローカル版では復元できず、
-- アイドルだからと落とすと利用者が困る。
-- そのため`lib/container-socket-activation.nix`はアイドル停止を持たない。
-- プロセスは生かしたまま、メモリだけを返させる。
--
-- = アイドルの測り方
--
-- `/prompt`の`queue_remaining`が0でないなら、実行中か待機中のものがあるので動いている。
--
-- 0の時に「いつから空か」を自分の観測だけで決めてはいけない。
-- 確認は数分おきなので、その隙間に始まって終わった生成を丸ごと見落とす。
-- 生成の直後に「ずっと空だった」と誤って判断して降ろすのが、一番やってはいけない挙動である。
--
-- 代わりにComfyUI自身が記録した時刻を読む。
-- `execution_start`と`execution_success`には`add_message`がミリ秒の実時刻を打っていて、
-- `/history`の各件の`status.messages`から取れる。
-- これを使えば確認の間隔と無関係に最後の活動が分かる。
--
-- = 何を解放するか
--
-- `/free`へ`unload_models`と`free_memory`を立てて投げる。
-- 前者がVRAMの重みを降ろし、後者が実行結果のキャッシュを捨ててRAMを返す。
-- ComfyUI本体の`main.py`の`prompt_worker`はキューが空でもフラグを読みに行くので、
-- 何も実行していない待機中でもこの要求は効く。
-- 降ろした後の`gc.collect`と`soft_empty_cache`も本体がやる。
--
-- ただしRSSが起動直後の水準まで戻ることは期待できない。
-- Pythonのアロケータが確保済みの領域をOSへ返しきるとは限らないためである。
-- 完全に返すにはプロセスの終了が要るが、それは上に書いた理由で採らない。
--
-- = なぜ常駐するか
--
-- タイマーで起こす形だと、
-- 最後に動いていた時刻をプロセスの外、
-- つまり`/run`のファイルへ置き直す必要がある。
-- 起動しっぱなしなら引数で持ち回すだけで済む。
--
-- = なぜモジュールを分けるか
--
-- このモジュールはHTTPと時計とループだけを持ち、
-- 応答の解釈は`IdleFreeMemory.Response`へ、
-- アイドルの判定は`IdleFreeMemory.State`へ置いてある。
-- どちらもテストで固定したい対象で、
-- 待ち続けるループと同居していると回さずに試せないためである。
module IdleFreeMemory.Run
  ( RequestFailure (..)
  , run
  , freeIfNeeded
  ) where

import Himari
import IdleFreeMemory.Config (Config (..))
import IdleFreeMemory.Response (ResponseFailure, latestActivity, queueRemaining)
import IdleFreeMemory.State
  ( Decision (..)
  , IdleState (..)
  , Observation (..)
  , initialState
  , nextState
  )
import Network.HTTP.Simple

-- | HTTPは通ったが、応答を受け取れる状態ではなかった。
data RequestFailure
  = -- | 成功ではない状態コードが返った。パスと状態コードを持つ。
    UnexpectedStatus Text Int
  | -- | 本文をJSONとして読めなかった。パスとデコーダの理由を持つ。
    UndecodableBody Text Text
  deriving stock (Eq, Show)

instance Exception RequestFailure where
  displayException = \case
    UnexpectedStatus path status -> convert path <> "が状態コード" <> show status <> "を返しました"
    UndecodableBody path reason -> convert path <> "の応答を読めませんでした: " <> convert reason

-- | 周回の中で吸収してよい一時的な失敗(通信、状態コードや本文、応答の形)なら、記録用の文言を返す。
--
-- ComfyUIの再起動中や、モデルの読み込みで応答が詰まっている間は届かない。
-- それらは次の周回で回復するので、周回の中で吸収する。
--
-- 接続の失敗や時間切れや途中での切断は`HttpException`に、
-- 状態コードと本文の問題は`RequestFailure`に、
-- 応答の形の問題は`ResponseFailure`に入る。
-- それ以外の例外はこちらの不具合なので、握り潰さずに上へ通してユニットごと落とす。
transientFailure :: SomeException -> Maybe Text
transientFailure exception
  -- 既定の表示は要求の全フィールドを何行にも渡って並べるので、
  -- 周回ごとに出るログとしては中身の理由だけにする。
  --
  -- 同じ`HttpException`でも`InvalidUrlException`は吸収しない。
  -- 接続先の値が壊れている時にしか起きず、待っても直らないためである。
  | Just (HttpExceptionRequest _ content) <- fromException exception = Just (convert (show content))
  | Just (failure :: RequestFailure) <- fromException exception = Just (describe failure)
  | Just (failure :: ResponseFailure) <- fromException exception = Just (describe failure)
  | otherwise = Nothing
 where
  describe :: (Exception e) => e -> Text
  describe = convert . displayException

-- | 待ち続けて、アイドルが続いたら解放を要求する。返らない。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => Config -> m ()
run config = do
  -- 接続先が壊れていると全ての周回が同じ理由で失敗し続けるので、
  -- 秒数の環境変数と同じく起動の時点で落とす。
  let probe :: Maybe Request
      probe = parseRequest (convert ("http://" <> config.authority <> "/"))
  when (isNothing probe) do
    logErrorN ("COMFYUI_AUTHORITYを接続先として読めません: " <> config.authority)
    throwM (ExitFailure 1)
  initial <- initialIdleState config.authority
  logInfoN
    ( convert (show config.pollIntervalSeconds)
        <> "秒ごとに確認し、"
        <> convert (show config.idleThreshold)
        <> "のアイドルで解放します"
    )
  watchFrom initial
 where
  watchFrom current = do
    -- 確認より先に待つ。
    -- ComfyUIの起動を待つ経路をここに書かずに済む。
    --
    -- 何かの完了を待つのではなく、決まった周期で見に行くこと自体が仕事なので、
    -- 同期変数やリトライではなく固定の待ちにする。
    -- 活動時刻はComfyUI自身の記録から取るので、
    -- 周期がずれても取りこぼしは起きない。
    threadDelay (config.pollIntervalSeconds * 1000000)
    observed <- tryJust transientFailure (observe config.authority)
    next <- case observed of
      Left reason -> do
        -- 次の周回で回復するので、記録だけ残して続ける。
        logWarnN ("状態を取得できませんでした: " <> reason)
        pure current
      Right observation -> do
        for_ observation.latest \latest ->
          when (observation.now < latest) do
            -- `nextState`が現在時刻へ倒すので判定は狂わないが、
            -- 倒したこと自体は時刻ずれの兆候なので記録しておく。
            logWarnN
              ( "履歴の時刻が"
                  <> convert (show (diffUTCTime latest observation.now))
                  <> "だけ未来を指しています"
              )
        let (updated, decision) = nextState config.idleThreshold observation current
        freeIfNeeded (postFree config.authority) decision updated
    watchFrom next

-- | 1周回分の観測を行う。
observe :: (MonadIO m, MonadThrow m) => Text -> m Observation
observe authority = do
  remaining <- getJson authority "/prompt" >>= either throwM pure . queueRemaining
  let busy = 0 < remaining
  -- busyなら`nextState`は履歴を見ずに現在時刻で上書きするので、
  -- 引いても結果に影響しない。
  -- 数分に1回のループバックHTTPで絶対量は小さいが、
  -- 相手はComfyUIのメインループと同じプロセスのハンドラなので、
  -- 生成中に余計な仕事をさせない。
  latest <-
    if busy
      then pure Nothing
      else fetchLatestActivity authority
  now <- liftIO getCurrentTime
  pure Observation{now, busy, latest}

-- | ComfyUIが記録した最後の活動時刻を取る。
--
-- `max_items=1`で新しい方の1件だけを引くことと、
-- `latestActivity`がその応答を読むことは対で動く前提なので、
-- 引く場所を1つにまとめておく。
fetchLatestActivity :: (MonadIO m, MonadThrow m) => Text -> m (Maybe UTCTime)
fetchLatestActivity authority =
  getJson authority "/history?max_items=1" >>= either throwM pure . latestActivity

-- | ループへ入る前の状態を作る。
--
-- 履歴から何を決めるかは`initialState`が持つ。
-- ここはComfyUIがまだ起動しきっていない場合に、
-- 履歴が無いものとして扱うことだけを受け持つ。
initialIdleState :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => Text -> m IdleState
initialIdleState authority = do
  fetched <- tryJust transientFailure (fetchLatestActivity authority)
  latest <- case fetched of
    Left reason -> do
      logWarnN ("起動時の履歴を取得できませんでした: " <> reason)
      pure Nothing
    Right latest -> pure latest
  now <- liftIO getCurrentTime
  pure (initialState now latest)

-- | 必要なら解放を要求して、通った時だけ`freed`を立てる。
--
-- 要求そのものを引数で受け取るのは、
-- ここが`nextState`と対になる不変条件を持つからである。
-- あちらは`freed`を立てず、立てるのはこちらで、
-- しかも要求が実際に通った後に限る。
-- 失敗した周回でフラグだけ進めると、
-- 次の活動があるまで再試行できなくなる。
--
-- 通信の失敗だけを吸収する。
-- それ以外の例外はこちらの不具合なので、握り潰さずに上へ通す。
freeIfNeeded :: (MonadLogger m, MonadUnliftIO m) => m () -> Decision -> IdleState -> m IdleState
freeIfNeeded _ Hold current = pure current
freeIfNeeded requestFree RequestFree current = do
  result <- tryJust transientFailure requestFree
  case result of
    Left reason -> do
      logWarnN ("メモリの解放を要求できませんでした: " <> reason)
      pure current
    Right () -> do
      logInfoN "アイドルが続いているのでメモリの解放を要求しました"
      pure current{freed = True}

-- | GETしてJSONを読む。
--
-- ComfyUIのAPIには型が無いので`Value`のまま返して、
-- 必要な形かどうかは`IdleFreeMemory.Response`側で確かめる。
--
-- 応答待ちの上限はhttp-clientの既定の30秒に任せる。
-- 相手は同じコンテナの中のループバックなので、
-- 返らないのは相手が詰まっているか落ちている時だけである。
getJson :: (MonadIO m, MonadThrow m) => Text -> Text -> m Value
getJson authority path = do
  request <- parseRequest (convert ("http://" <> authority <> path))
  body <- successBody path =<< httpLBS request
  either (throwM . UndecodableBody path . convert) pure (eitherDecode body)

-- | `/free`へ解放の指示を投げる。
--
-- ComfyUI本体の`main.py`は`flags.get("unload_models", free_memory)`の形で、
-- `free_memory`を`unload_models`の既定値として読む。
-- つまり`free_memory`だけでも同じ結果になるが、
-- どちらを意図したのかが読めなくなるので両方書く。
postFree :: (MonadIO m, MonadThrow m) => Text -> m ()
postFree authority = do
  request <- parseRequest (convert ("POST http://" <> authority <> path))
  let payload = [aesonQQ|{"unload_models": true, "free_memory": true}|]
  -- 本文は空なので捨てる。
  void (successBody path =<< httpLBS (setRequestBodyJSON payload request))
 where
  path = "/free"

-- | 応答の本文を返す。成功の状態でなければ例外にする。
successBody :: (MonadThrow m) => Text -> Response LazyByteString -> m LazyByteString
successBody path response
  | getResponseStatusCode response `div` 100 == 2 = pure (getResponseBody response)
  | otherwise = throwM (UnexpectedStatus path (getResponseStatusCode response))
