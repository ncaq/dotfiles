-- | 引数の解釈から終了までのテスト。
--
-- `sweep`はゴミ箱ごとに実行ファイル自身を`clean-here`として起動するので、
-- cabalがテストのPATHへ入れる、ビルドした`trash-empty-stray`を使う。
--
-- テストは一般ユーザとして走るので、他の所有者の権限へ落とす場面はここでは確かめられない。
-- そこは`test/nixos-boot/script/trash-empty.nix`が実際のサービスで確かめる。
module Spec.CliSpec (tests) where

import Fixture (Age (..), listTree, putEntry, runQuiet, withRoot)
import Himari
import System.Posix.Files (createSymbolicLink)
import Test.Sandwich
import TrashEmptyStray.Cli (runWith)

-- | ビルドした実行ファイルを`clean-here`の起動に使って、ログを出さずに実行する。
runBuilt :: (MonadIO m) => [String] -> m ()
runBuilt = runQuiet . runWith "trash-empty-stray"

tests :: TopSpec
tests = describe "runWith" do
  it "起点の下の全てのゴミ箱から期限切れを消して、空になったゴミ箱を消す" do
    withRoot \root -> do
      putEntry (root </> "a/.Trash-1000") "old" Expired
      putEntry (root </> "b/c/.Trash-1000") "old" Expired
      putEntry (root </> "b/c/.Trash-1000") "new" Fresh
      runBuilt ["sweep", "--days", "7", root]
      listTree root
        >>= ( `shouldBe`
                [ "a"
                , "b"
                , "b/c"
                , "b/c/.Trash-1000"
                , "b/c/.Trash-1000/files"
                , "b/c/.Trash-1000/files/new"
                , "b/c/.Trash-1000/info"
                , "b/c/.Trash-1000/info/new.trashinfo"
                ]
            )
  it "掃除できないゴミ箱があっても残りを掃除して、1で終わる" do
    withRoot \root -> do
      -- `info`がディレクトリではないので、`trash-empty`が失敗する。
      createDirectoryIfMissing True (root </> "a/.Trash-1000")
      writeBinaryFile (root </> "a/.Trash-1000/info") ""
      putEntry (root </> "b/.Trash-1000") "old" Expired
      try (runBuilt ["sweep", "--days", "7", root]) >>= (`shouldBe` Left (ExitFailure 1))
      listTree root >>= (`shouldBe` ["a", "a/.Trash-1000", "a/.Trash-1000/info", "b"])
  it "ゴミ箱がシンボリックリンクなら掃除しない" do
    withRoot \root -> do
      putEntry (root </> "outside/.Trash-1000") "old" Expired
      createDirectoryIfMissing True (root </> "inside")
      liftIO (createSymbolicLink (root </> "outside/.Trash-1000") (root </> "inside/.Trash-1000"))
      runBuilt ["sweep", "--days", "7", root </> "inside"]
      doesFileExist (root </> "outside/.Trash-1000/files/old") >>= (`shouldBe` True)
  it "日数の指定が無ければ1で終わる" do
    try (runBuilt ["sweep", "/nonexistent"]) >>= (`shouldBe` Left (ExitFailure 1))
