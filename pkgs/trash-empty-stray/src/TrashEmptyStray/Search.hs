-- | ゴミ箱の探索。
module TrashEmptyStray.Search
  ( findTrashDirs
  ) where

import Data.ByteString qualified as B
import Data.List (sort)
import Himari
import System.Posix.Directory.ByteString (closeDirStream, openDirStream)
import System.Posix.Directory.Internals
  ( dirEntName
  , dirEntType
  , isDirectoryType
  , isUnknownType
  , readDirStreamWith
  )
import System.Posix.Files.ByteString (deviceID, getSymbolicLinkStatus, isDirectory)
import System.Posix.Types (DeviceID)
import TrashEmptyStray.RawPath (RawPath, appendName, fromRawPath, toRawPath)
import TrashEmptyStray.TrashDirName (isHomeTrashPath, isTrashDirName)

-- | これから中身を読むディレクトリと、その起点のデバイス。
data Pending = Pending RawPath DeviceID

-- | ディレクトリの中の1つの名前が、ディレクトリかどうかについて読み取りで分かったこと。
data Kind
  = -- | ディレクトリである。シンボリックリンクは含まない。
    Directory
  | -- | ファイルシステムが種類を返さないので、個別に調べないと分からない。
    Unknown

-- | 1つのディレクトリを読んで分かったこと。
data Visited = Visited
  { trashDirs :: [RawPath]
  -- ^ 見つけたゴミ箱。
  , children :: [Pending]
  -- ^ 続けて読むディレクトリ。
  }

-- | 起点の下から`.Trash-<uid>`の形のディレクトリを探して、パスの順に返す。
--
-- - シンボリックリンクは辿らない。リンクの先を掃除の対象にしないためである
-- - 起点と違うデバイスのディレクトリへは降りない。
--   ネットワークマウントやスナップショットのサブボリュームを辿らないためである
-- - 見つけたゴミ箱の中へは降りない
-- - ホームのゴミ箱(`.local/share/Trash`)の中へは降りない。
--   捨てたディレクトリの中にあるゴミ箱まで掃除すると、捨てたものの中身を書き換えてしまう
-- - 存在しない起点と、読めないディレクトリは、警告を出して飛ばす
--
-- ディレクトリの読み取りはCPUのコア数だけ並列に行う。
-- 読むべきディレクトリを共有のスタックに積み、
-- スタックが空で処理中のものも無くなった時に全員が終わる。
-- キューではなくスタックにして深さ優先に近い順で辿るのは、
-- 幅優先だとある深さのディレクトリを全て抱えることになり、メモリを大きく使うためである。
-- スタックへは1つのディレクトリを読み終えるごとにまとめて書く。
-- 名前ごとに書くと、書き込みの競合で並列にした分が打ち消される。
findTrashDirs :: (MonadLogger m, MonadUnliftIO m) => [FilePath] -> m [FilePath]
findTrashDirs roots = do
  stack <- newTVarIO []
  unfinished <- newTVarIO (0 :: Int)
  found <- newTVarIO []
  let
    pop =
      readTVar stack >>= \case
        pending : rest -> Just pending <$ writeTVar stack rest
        [] -> readTVar unfinished >>= \count -> Nothing <$ checkSTM (count == 0)
    -- 読み終えたディレクトリの結果を書いて、そのディレクトリを処理中から外す。
    commit visited = atomically do
      unless (null visited.trashDirs) (modifyTVar' found (visited.trashDirs <>))
      unless (null visited.children) (modifyTVar' stack (visited.children <>))
      modifyTVar' unfinished (+ (length visited.children - 1))
    worker =
      atomically pop >>= \case
        Just pending -> do
          -- 読めないディレクトリは`visit`が警告を出して飛ばしている。
          -- それ以外の例外でも処理中から外さないと、他の全員が終わりを待ち続ける。
          visited <-
            visit pending `catchAny` \(SomeException exception) ->
              Visited [] [] <$ logErrorN ("探索に失敗しました: " <> convert (displayException exception))
          commit visited
          worker
        Nothing -> pure ()
  rootPending <- fmap catMaybes . for roots $ \root -> do
    rawRoot <- toRawPath root
    tryIO (liftIO (getSymbolicLinkStatus rawRoot)) >>= \case
      Right status | isDirectory status -> pure (Just (Pending rawRoot (deviceID status)))
      Right _ -> Nothing <$ logWarnN (convert root <> "はディレクトリではないので探しません")
      Left exception -> Nothing <$ warn rawRoot exception
  atomically do
    writeTVar stack rootPending
    writeTVar unfinished (length rootPending)
  workers <- getNumCapabilities
  replicateConcurrently_ workers worker
  readTVarIO found >>= fmap sort . traverse fromRawPath

-- | 1つのディレクトリを読んで、見つけたゴミ箱と、続けて読むディレクトリを返す。
visit :: (MonadLogger m, MonadUnliftIO m) => Pending -> m Visited
visit (Pending directory device) = do
  entries <- readEntries directory `catchIO` \exception -> [] <$ warn directory exception
  results <- for entries \(name, kind) -> do
    let
      path = appendName directory name
      -- 降りて良いのは、起点と同じデバイスにある本物のディレクトリだけである。
      descendIfSameDevice =
        tryIO (liftIO (getSymbolicLinkStatus path)) >>= \case
          Left exception -> Visited [] [] <$ warn path exception
          Right status
            | isDirectory status && deviceID status == device ->
                pure (Visited [] [Pending path device])
            | otherwise -> pure (Visited [] [])
    case kind of
      _ | isHomeTrashPath path -> pure (Visited [] [])
      Directory
        | isTrashDirName name -> pure (Visited [path] [])
        | otherwise -> descendIfSameDevice
      Unknown
        | isTrashDirName name ->
            tryIO (liftIO (getSymbolicLinkStatus path)) >>= \case
              Left exception -> Visited [] [] <$ warn path exception
              Right status -> pure (Visited [path | isDirectory status] [])
        | otherwise -> descendIfSameDevice
  pure Visited{trashDirs = foldMap (.trashDirs) results, children = foldMap (.children) results}

warn :: (MonadIO m, MonadLogger m) => RawPath -> IOException -> m ()
warn path exception = do
  displayPath <- fromRawPath path
  logWarnN
    (convert displayPath <> "を読めないので飛ばします: " <> convert (displayException exception))

-- | ディレクトリの中の、ディレクトリかもしれない名前を、読み取りで分かった種類と共に返す。
--
-- `.`と`..`と、ディレクトリではないと分かっているものは除く。
--
-- 名前の一覧だけを取って1つずつ種類を調べると、ファイルの数だけシステムコールが増える。
-- ファイルが大半を占めるので、ディレクトリを読んだ時に一緒に返ってくる種類を使い、
-- ディレクトリではないものは名前を取り出しもしない。
-- 種類を取る関数は`unix`の内部向けのモジュールにしか無い。
readEntries :: (MonadUnliftIO m) => RawPath -> m [(ByteString, Kind)]
readEntries directory = liftIO do
  bracket (openDirStream directory) closeDirStream \stream ->
    let
      readEntry entry = do
        entryType <- dirEntType entry
        let
          named kind = do
            name <- dirEntName entry >>= B.packCString
            pure (if name `elem` [".", ".."] then Nothing else Just (name, kind))
        if
          | isDirectoryType entryType -> named Directory
          | isUnknownType entryType -> named Unknown
          | otherwise -> pure Nothing
      go entries =
        readDirStreamWith readEntry stream >>= \case
          Nothing -> pure entries
          Just entry -> go (maybe entries (: entries) entry)
     in
      go []
