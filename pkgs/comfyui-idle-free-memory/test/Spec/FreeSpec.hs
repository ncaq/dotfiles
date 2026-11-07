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
import IdleFreeMemory.Run (RequestFailure (..), freeIfNeeded)
import IdleFreeMemory.State (Decision (..), IdleState (..))
import Network.HTTP.Simple (HttpException (..))
import Test.Sandwich

idleState :: IdleState
idleState = IdleState{lastActivity = posixSecondsToUTCTime 1000, freed = False}

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
  for_
    [ ("接続できない", toException (InvalidUrlException "http://127.0.0.1:8188/free" "テスト"))
    , ("成功ではない状態コード", toException (UnexpectedStatus "/free" 500))
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
