-- | 絶対パスのディレクトリと`FilePath`の変換。
module TrashEmptyStray.AbsDir
  ( AbsDir
  , parseAbsDirPath
  , absDirFilePath
  ) where

import Himari
import OsPath (Abs, Dir, Path, fromAbsDir, parseAbsDir)
import System.OsPath.Posix (decodeFS, encodeFS)

-- | 絶対パスのディレクトリ。
--
-- 探索は百万を超えるディレクトリを辿るので、パスを文字のリストである`FilePath`では持たない。
-- 絶対パスであることとディレクトリであることを型で区別できるので、
-- 名前だけの相対パスや、ディレクトリかどうか確かめていないものを取り違えることも防げる。
type AbsDir = Path Abs Dir

-- | 引数などで受け取った`FilePath`を解釈する。絶対パスでなければ例外を投げる。
parseAbsDirPath :: (MonadIO m, MonadThrow m) => FilePath -> m AbsDir
parseAbsDirPath path = liftIO (encodeFS path) >>= parseAbsDir

-- | 他のコマンドへ渡したりログへ出したりするための`FilePath`にする。末尾の区切りは付けない。
absDirFilePath :: (MonadIO m) => AbsDir -> m FilePath
absDirFilePath = fmap dropTrailingPathSeparator . liftIO . decodeFS . fromAbsDir
