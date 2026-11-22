-- | ゴミ箱の探索のテスト。
module Spec.SearchSpec (tests) where

import Data.List (sort)
import Fixture (runQuiet, withRoot)
import Himari
import System.Posix.Files (createSymbolicLink)
import Test.Sandwich
import TrashEmptyStray.AbsDir (absDirFilePath, parseAbsDirPath)
import TrashEmptyStray.Search (findTrashDirs)

-- | `FilePath`の起点から探して、見つけたものを`FilePath`で返す。ログは出さない。
findIn :: (MonadIO m) => [FilePath] -> m [FilePath]
findIn roots =
  runQuiet (traverse parseAbsDirPath roots >>= findTrashDirs >>= traverse absDirFilePath)

tests :: TopSpec
tests = describe "findTrashDirs" do
  it "深い階層にあるゴミ箱を全て見つけて、パスの順に返す" do
    withRoot \root -> do
      let expected = [root </> ".Trash-0", root </> "a/b/c/.Trash-1000", root </> "a/.Trash-1000"]
      for_ expected (createDirectoryIfMissing True)
      createDirectoryIfMissing True (root </> "a/b/other")
      findIn [root] >>= (`shouldBe` sort expected)
  it "見つけたゴミ箱の中へは降りない" do
    withRoot \root -> do
      createDirectoryIfMissing True (root </> ".Trash-1000/files/trashed/.Trash-1000")
      findIn [root] >>= (`shouldBe` [root </> ".Trash-1000"])
  it "ホームのゴミ箱の中へは降りない" do
    withRoot \root -> do
      createDirectoryIfMissing True (root </> "user/.local/share/Trash/files/trashed/.Trash-1000")
      createDirectoryIfMissing True (root </> "user/.local/share/other/.Trash-1000")
      findIn [root]
        >>= (`shouldBe` [root </> "user/.local/share/other/.Trash-1000"])
  it "ゴミ箱の名前でもディレクトリでなければ拾わない" do
    withRoot \root -> do
      writeBinaryFile (root </> ".Trash-1000") ""
      findIn [root] >>= (`shouldBe` [])
  it "シンボリックリンクは辿らず、リンク自体も拾わない" do
    withRoot \root -> do
      createDirectoryIfMissing True (root </> "outside/.Trash-1000")
      createDirectoryIfMissing True (root </> "inside")
      liftIO (createSymbolicLink (root </> "outside") (root </> "inside/link"))
      liftIO (createSymbolicLink (root </> "outside/.Trash-1000") (root </> "inside/.Trash-1000"))
      findIn [root </> "inside"] >>= (`shouldBe` [])
  it "存在しない起点は飛ばして、残りの起点を探す" do
    withRoot \root -> do
      createDirectoryIfMissing True (root </> "exists/.Trash-1000")
      findIn [root </> "missing", root </> "exists"]
        >>= (`shouldBe` [root </> "exists/.Trash-1000"])
  it "起点が無ければ何も返さない" do
    findIn [] >>= (`shouldBe` [])
