-- | テストで使う偽のゴミ箱と、ログを出さない実行。
module Fixture
  ( Age (..)
  , putEntry
  , listTree
  , runQuiet
  , withRoot
  ) where

import Data.List (sort)
import Data.Text.IO.Utf8 (writeFile)
import Himari hiding (writeFile)

-- | エントリを捨てた時期。
data Age
  = -- | どんな保持日数でも期限切れになる昔。
    Expired
  | -- | どんな保持日数でも期限切れにならない先。
    Fresh
  deriving stock (Eq, Show)

-- | ゴミ箱へ、`trash-put`が作るのと同じ形でエントリを1つ置く。
putEntry :: (MonadIO m) => FilePath -> FilePath -> Age -> m ()
putEntry trashDir name age = do
  createDirectoryIfMissing True (trashDir </> "info")
  createDirectoryIfMissing True (trashDir </> "files")
  liftIO (writeFile (trashDir </> "files" </> name) "content\n")
  liftIO
    ( writeFile
        (trashDir </> "info" </> name <> ".trashinfo")
        ("[Trash Info]\nPath=" <> convert name <> "\nDeletionDate=" <> deletionDate <> "\n")
    )
 where
  deletionDate = case age of
    Expired -> "2000-01-01T00:00:00"
    Fresh -> "2999-01-01T00:00:00"

-- | ディレクトリの下にある全てのパスを、起点からの相対パスの順で返す。
listTree :: (MonadIO m) => FilePath -> m [FilePath]
listTree root = sort <$> go ""
 where
  go relative = do
    names <- listDirectory (root </> relative)
    concat <$> for names \name -> do
      let path = relative </> name
      isRealDirectory <-
        (&&) <$> doesDirectoryExist (root </> path) <*> (not <$> pathIsSymbolicLink (root </> path))
      (path :) <$> if isRealDirectory then go path else pure []

-- | ログを端末へ出さずに実行する。
runQuiet :: (MonadIO m) => Himari SimpleEnv a -> m a
runQuiet = runSimpleEnvWith (\_ _ _ _ -> pure ())

-- | 一時ディレクトリを作って実行する。
withRoot :: (MonadUnliftIO m) => (FilePath -> m a) -> m a
withRoot = withSystemTempDirectory "trash-empty-stray-test"
