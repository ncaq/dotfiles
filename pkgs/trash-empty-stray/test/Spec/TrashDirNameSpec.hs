-- | 探す対象にするゴミ箱の名前のテスト。
--
-- ここを緩めると、ゴミ箱ではないディレクトリの`info`と`files`を掃除してしまう。
module Spec.TrashDirNameSpec (tests) where

import Himari
import Test.Sandwich
import TrashEmptyStray.TrashDirName (isHomeTrashPath, isTrashDirName)

tests :: TopSpec
tests = do
  isTrashDirNameTests
  isHomeTrashPathTests

isHomeTrashPathTests :: TopSpec
isHomeTrashPathTests = describe "isHomeTrashPath" do
  it "ホームのゴミ箱を指すパスを見分ける" do
    filter isHomeTrashPath ["/home/ncaq/.local/share/Trash", "/root/.local/share/Trash"]
      `shouldBe` ["/home/ncaq/.local/share/Trash", "/root/.local/share/Trash"]
  it "末尾が揃っていないパスは違うとする" do
    filter
      isHomeTrashPath
      ["/home/ncaq/Trash", "/home/ncaq/.local/share/Trash/files", "/home/ncaq/.local/share/Trash2"]
      `shouldBe` []

isTrashDirNameTests :: TopSpec
isTrashDirNameTests = describe "isTrashDirName" do
  it "uidの付いた名前を拾う" do
    filter isTrashDirName [".Trash-0", ".Trash-1000", ".Trash-65534"]
      `shouldBe` [".Trash-0", ".Trash-1000", ".Trash-65534"]
  it "uidが数字だけでない名前は拾わない" do
    filter isTrashDirName [".Trash-", ".Trash-ncaq", ".Trash-1000x", ".Trash--1"] `shouldBe` []
  it "別の形のゴミ箱の名前は拾わない" do
    filter isTrashDirName [".Trash", "Trash", "Trash-1000", ".trash-1000", "x.Trash-1000"]
      `shouldBe` []
