-- | ゴミ箱1つの掃除のテスト。
--
-- 期限の判定は`trash-empty`の実物に任せている。
module Spec.CleanSpec (tests) where

import Fixture (Age (..), listTree, putEntry, runQuiet, withRoot)
import Himari
import Test.Sandwich
import TrashEmptyStray.Clean (cleanTrashDir)
import TrashEmptyStray.RetentionDays (RetentionDays (..))
import TrashEmptyStray.TrashDir (atPath)

-- | 一時ディレクトリの中のゴミ箱を用意して掃除し、一時ディレクトリに残ったものを返す。
cleaned :: (MonadUnliftIO m) => (FilePath -> m ()) -> m [FilePath]
cleaned prepare = withRoot \root -> do
  let trashDir = root </> ".Trash-1000"
  prepare trashDir
  runQuiet (cleanTrashDir (RetentionDays 7) (atPath trashDir))
  listTree root

tests :: TopSpec
tests = describe "cleanTrashDir" do
  it "期限切れと新しいものが混ざっていると、新しいものとゴミ箱が残る" do
    cleaned (\trashDir -> putEntry trashDir "old" Expired *> putEntry trashDir "new" Fresh)
      >>= ( `shouldBe`
              [ ".Trash-1000"
              , ".Trash-1000/files"
              , ".Trash-1000/files/new"
              , ".Trash-1000/info"
              , ".Trash-1000/info/new.trashinfo"
              ]
          )
  it "期限切れだけだと、ゴミ箱ごと消える" do
    cleaned (\trashDir -> putEntry trashDir "old" Expired) >>= (`shouldBe` [])
  it "最初から空だと、ゴミ箱ごと消える" do
    cleaned
      ( \trashDir -> do
          createDirectoryIfMissing True (trashDir </> "info")
          createDirectoryIfMissing True (trashDir </> "files")
      )
      >>= (`shouldBe` [])
  it "infoもfilesも無いと、ゴミ箱ごと消える" do
    cleaned (createDirectoryIfMissing True) >>= (`shouldBe` [])
  it "知らないファイルがあると、ゴミ箱が残る" do
    cleaned
      ( \trashDir -> do
          createDirectoryIfMissing True (trashDir </> "info")
          writeBinaryFile (trashDir </> "directorysizes") ""
      )
      >>= (`shouldBe` [".Trash-1000", ".Trash-1000/directorysizes"])
  it "infoが空でなければ、空のfilesも残す" do
    cleaned
      ( \trashDir -> do
          putEntry trashDir "new" Fresh
          removeFile (trashDir </> "files/new")
      )
      >>= ( `shouldBe`
              [ ".Trash-1000"
              , ".Trash-1000/files"
              , ".Trash-1000/info"
              , ".Trash-1000/info/new.trashinfo"
              ]
          )
