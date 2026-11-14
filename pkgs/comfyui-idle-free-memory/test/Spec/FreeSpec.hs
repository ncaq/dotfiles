-- | `freeIfNeeded`のテスト。
--
-- `IdleFreeMemory.State`は「`freed`を立てるのは要求が通った後の呼び出し側である」と書き、
-- そちらのテストが遷移の側を固定している。
-- その対になる呼び出し側がここである。
--
-- 片側だけを固定していると、
-- 要求を例外の捕捉の外へ出しても、
-- 失敗の側で状態を進めてしまっても、テストは通る。
-- 実機では解放が次の活動まで再試行されなくなるだけなので気付けない。
module Spec.FreeSpec (tests) where

import Himari
import IdleFreeMemory.Response (ResponseFailure (..))
import IdleFreeMemory.Run (RequestFailure (..), freeIfNeeded)
import IdleFreeMemory.State (Decision (..), IdleState (..))
import Network.HTTP.Client (HttpExceptionContent (..))
import Network.HTTP.Simple (HttpException (..), defaultRequest)
import Test.Sandwich

idleState :: IdleState
idleState =
  IdleState{lastActivity = posixSecondsToUTCTime 1000, freed = False, seenHistory = Nothing}

-- | 想定していない失敗。
data Unexpected = Unexpected
  deriving stock (Show)

instance Exception Unexpected

-- | 呼ばれた回数を数える要求と、その回数を読む操作を作る。
countingRequest :: (MonadIO m) => m (IO (), IO Int)
countingRequest = do
  calls <- newIORef (0 :: Int)
  pure (modifyIORef' calls (+ 1), readIORef calls)

tests :: TopSpec
tests = describe "freeIfNeeded" do
  it "要求しない時は何もしない" do
    (request, calls) <- countingRequest
    runSimpleNoLogEnv (freeIfNeeded (liftIO request) Hold idleState) >>= (`shouldBe` idleState)
    liftIO calls >>= (`shouldBe` 0)
  it "要求が通ったら解放済みにする" do
    (request, calls) <- countingRequest
    runSimpleNoLogEnv (freeIfNeeded (liftIO request) RequestFree idleState)
      >>= (`shouldBe` idleState{freed = True})
    liftIO calls >>= (`shouldBe` 1)
  -- 吸収する例外の分岐を全て通す。
  -- 実機で起こる接続拒否と時間切れは`HttpExceptionRequest`になる。
  for_
    [
      ( "接続できない"
      , toException
          (HttpExceptionRequest defaultRequest (ConnectionFailure (toException (userError "拒否"))))
      )
    , ("時間切れ", toException (HttpExceptionRequest defaultRequest ResponseTimeout))
    , ("成功ではない状態コード", toException (UnexpectedStatus "/free" 500))
    , ("本文を読めない", toException (UndecodableBody "/free" "テスト"))
    , ("応答の形が違う", toException PromptNotObject)
    ]
    \(caseName, failure) ->
      it ("要求に失敗したら解放済みにしない: " <> caseName) do
        -- 失敗した周回でフラグだけ進めると、次の活動まで再試行できなくなる。
        runSimpleNoLogEnv (freeIfNeeded (throwM failure) RequestFree idleState)
          >>= (`shouldBe` idleState)
  it "想定していない失敗は握り潰さない" do
    -- 通信の失敗だけを吸収する。
    -- それ以外はこちらの不具合なので、握り潰さずにユニットごと落とす。
    runSimpleNoLogEnv (freeIfNeeded (throwM Unexpected) RequestFree idleState)
      `shouldThrow` \Unexpected -> True
  it "URLが不正なら吸収しない" do
    -- 接続先の値が壊れている時にしか起きず、待っても直らない。
    runSimpleNoLogEnv
      ( freeIfNeeded
          (throwM (InvalidUrlException "http://[::1]:8188/free" "テスト"))
          RequestFree
          idleState
      )
      `shouldThrow` \case
        InvalidUrlException _ _ -> True
        HttpExceptionRequest _ _ -> False
