-- | ゴミ箱の探索。
module TrashEmptyStray.Search
  ( findTrashDirs
  ) where

import Data.List (sort)
import Himari
import System.Posix.Files (deviceID, getSymbolicLinkStatus, isDirectory)
import System.Posix.Types (DeviceID)
import TrashEmptyStray.TrashDirName (isTrashDirName)

-- | これから中身を読むディレクトリと、その起点のデバイス。
data Pending = Pending FilePath DeviceID

-- | 起点の下から`.Trash-<uid>`の形のディレクトリを探して、パスの順に返す。
--
-- - シンボリックリンクは辿らない。リンクの先を掃除の対象にしないためである
-- - 起点と違うデバイスのディレクトリへは降りない。
--   ネットワークマウントやスナップショットのサブボリュームを辿らないためである
-- - 見つけたゴミ箱の中へは降りない
-- - 存在しない起点と、読めないディレクトリは、警告を出して飛ばす
--
-- ディレクトリの読み取りはCPUのコア数だけ並列に行う。
-- 読むべきディレクトリをキューに積み、
-- キューが空で処理中のものも無くなった時に全員が終わる。
findTrashDirs :: (MonadLogger m, MonadUnliftIO m) => [FilePath] -> m [FilePath]
findTrashDirs roots = do
  queue <- newTQueueIO
  unfinished <- newTVarIO (0 :: Int)
  found <- newTVarIO []
  let
    enqueue pending = atomically do
      modifyTVar' unfinished (+ 1)
      writeTQueue queue pending
    visit (Pending directory device) = do
      names <- listDirectory directory `catchIO` \exception -> [] <$ warn directory exception
      for_ names \name -> do
        let path = directory </> name
        tryIO (liftIO (getSymbolicLinkStatus path)) >>= \case
          Left exception -> warn path exception
          Right status
            | not (isDirectory status) -> pure ()
            | isTrashDirName name -> atomically (modifyTVar' found (path :))
            | deviceID status == device -> enqueue (Pending path device)
            | otherwise -> pure ()
    worker =
      join . atomically $
        (readTQueue queue <&> \pending -> (visit pending `finally` finish) *> worker)
          `orElse` (readTVar unfinished >>= \count -> pure () <$ checkSTM (count == 0))
    finish = atomically (modifyTVar' unfinished (subtract 1))
  for_ roots \root ->
    tryIO (liftIO (getSymbolicLinkStatus root)) >>= \case
      Right status | isDirectory status -> enqueue (Pending root (deviceID status))
      Right _ -> logWarnN (convert root <> "はディレクトリではないので探しません")
      Left exception -> warn root exception
  workers <- getNumCapabilities
  replicateConcurrently_ workers worker
  sort <$> readTVarIO found
 where
  warn :: (MonadLogger m) => FilePath -> IOException -> m ()
  warn path exception =
    logWarnN (convert path <> "を読めないので飛ばします: " <> convert (displayException exception))
