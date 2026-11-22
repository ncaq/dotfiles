-- | 探す対象にするゴミ箱の名前のテスト。
--
-- ここを緩めると、ゴミ箱ではないディレクトリの`info`と`files`を掃除してしまう。
module Spec.TrashDirNameSpec (tests) where

import Himari
import OsPath (absdir)
import System.OsString.Posix (pstr)
import Test.Sandwich
import TrashEmptyStray.TrashDirName (isHomeTrashDir, isTrashDirName)

tests :: TopSpec
tests = do
  isTrashDirNameTests
  isHomeTrashDirTests

isHomeTrashDirTests :: TopSpec
isHomeTrashDirTests = describe "isHomeTrashDir" do
  it "ホームのゴミ箱を見分ける" do
    let homeTrashDirs =
          [ [absdir|/home/ncaq/.local/share/Trash|]
          , [absdir|/root/.local/share/Trash|]
          ]
    filter isHomeTrashDir homeTrashDirs `shouldBe` homeTrashDirs
  it "末尾が揃っていないパスは違うとする" do
    filter
      isHomeTrashDir
      [ [absdir|/home/ncaq/Trash|]
      , [absdir|/home/ncaq/.local/share/Trash/files|]
      , [absdir|/home/ncaq/.local/share/Trash2|]
      , [absdir|/share/Trash|]
      , [absdir|/|]
      ]
      `shouldBe` []

isTrashDirNameTests :: TopSpec
isTrashDirNameTests = describe "isTrashDirName" do
  it "uidの付いた名前を拾う" do
    filter isTrashDirName [[pstr|.Trash-0|], [pstr|.Trash-1000|], [pstr|.Trash-65534|]]
      `shouldBe` [[pstr|.Trash-0|], [pstr|.Trash-1000|], [pstr|.Trash-65534|]]
  it "uidが数字だけでない名前は拾わない" do
    filter
      isTrashDirName
      [[pstr|.Trash-|], [pstr|.Trash-ncaq|], [pstr|.Trash-1000x|], [pstr|.Trash--1|]]
      `shouldBe` []
  it "別の形のゴミ箱の名前は拾わない" do
    filter
      isTrashDirName
      [[pstr|.Trash|], [pstr|Trash|], [pstr|Trash-1000|], [pstr|.trash-1000|], [pstr|x.Trash-1000|]]
      `shouldBe` []
