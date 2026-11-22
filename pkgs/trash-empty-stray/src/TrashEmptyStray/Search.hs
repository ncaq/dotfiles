-- | ゴミ箱の探索。
module TrashEmptyStray.Search
  ( findTrashDirs
  ) where

import Data.List (sort)
import Himari
import System.Posix.Files (deviceID, getSymbolicLinkStatus, isDirectory)
import System.Posix.Types (DeviceID)
import TrashEmptyStray.TrashDirName (isHomeTrashPath, isTrashDirName)

-- | これから中身を読むディレクトリと、その起点のデバイス。
data Pending = Pending FilePath DeviceID

-- | ディレクトリを読んで分かったこと。
data Visited = Visited
  { trashDirs :: [FilePath]
  -- ^ 見つけたゴミ箱。
  , children :: [Pending]
  -- ^ 続けて読むディレクトリ。
  }

instance Semigroup Visited where
  former <> latter =
    Visited
      { trashDirs = former.trashDirs <> latter.trashDirs
      , children = former.children <> latter.children
      }

instance Monoid Visited where
  mempty = Visited{trashDirs = [], children = []}

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
-- 並列にするために、まず起点から浅い階層だけを順に読んで、探す範囲をディレクトリの単位に分ける。
-- 分けたディレクトリを1つずつワーカーへ渡して、ワーカーはその下を1人で最後まで辿る。
-- ワーカーどうしは何も共有せず、それぞれが見つけたものを最後に集める。
findTrashDirs :: (MonadLogger m, MonadUnliftIO m) => [FilePath] -> m [FilePath]
findTrashDirs roots = do
  rootPending <- fmap catMaybes . for roots $ \root ->
    tryIO (liftIO (getSymbolicLinkStatus root)) >>= \case
      Right status | isDirectory status -> pure (Just (Pending root (deviceID status)))
      Right _ -> Nothing <$ logWarnN (convert root <> "はディレクトリではないので探しません")
      Left exception -> Nothing <$ warn root exception
  shallow <- splitIntoUnits rootPending
  beneath <- pooledForConcurrently shallow.children (walk . pure)
  pure (sort (shallow.trashDirs <> concat beneath))

-- | ワーカーへ渡す単位がこの数に届くまで、階層を順に読み進める。
--
-- 起点は数個しか無く、大きさも偏っているので、起点の単位では並列にならない。
-- 単位が少ないと、大きな単位を引いたワーカーだけが最後まで残って、並列にした分が活きない。
-- 多すぎると、分けるための順の読み取りが長くなる。
enoughUnits :: Int
enoughUnits = 4096

-- | 単位が十分な数になるまで1階層ずつ順に読み進めて、
-- そこまでに見つけたゴミ箱と、その先のディレクトリを返す。
splitIntoUnits :: (MonadLogger m, MonadUnliftIO m) => [Pending] -> m Visited
splitIntoUnits pending
  | null pending || length pending >= enoughUnits = pure mempty{children = pending}
  | otherwise = do
      visited <- fold <$> for pending visit
      deeper <- splitIntoUnits visited.children
      pure deeper{trashDirs = visited.trashDirs <> deeper.trashDirs}

-- | ディレクトリの下を最後まで順に辿って、見つけたゴミ箱を返す。
walk :: (MonadLogger m, MonadUnliftIO m) => [Pending] -> m [FilePath]
walk = go []
 where
  go found = \case
    [] -> pure found
    pending : rest -> do
      visited <- visit pending
      go (visited.trashDirs <> found) (visited.children <> rest)

-- | 1つのディレクトリを読んで、見つけたゴミ箱と、続けて読むディレクトリを返す。
visit :: (MonadLogger m, MonadUnliftIO m) => Pending -> m Visited
visit (Pending directory device) = do
  names <- listDirectory directory `catchIO` \exception -> [] <$ warn directory exception
  fmap fold . for names $ \name -> do
    let path = directory </> name
    tryIO (liftIO (getSymbolicLinkStatus path)) >>= \case
      Left exception -> mempty <$ warn path exception
      Right status
        | not (isDirectory status) -> pure mempty
        | isTrashDirName name -> pure mempty{trashDirs = [path]}
        | isHomeTrashPath path -> pure mempty
        -- 降りて良いのは、起点と同じデバイスにあるディレクトリだけである。
        | deviceID status == device -> pure mempty{children = [Pending path device]}
        | otherwise -> pure mempty

warn :: (MonadLogger m) => FilePath -> IOException -> m ()
warn path exception =
  logWarnN (convert path <> "を読めないので飛ばします: " <> convert (displayException exception))
