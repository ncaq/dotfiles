-- | ディレクトリの所有者の権限でのコマンドの実行のテスト。
--
-- テストは一般ユーザとして走るので、他の所有者の権限へ落とす場面はここでは確かめられない。
-- そこは`nixos-test.nix`が実際のサービスで確かめる。
module Spec.OwnerSpec (tests) where

import Fixture (withRoot)
import Himari
import System.Posix.Files (getFileStatus)
import Test.Sandwich
import TrashEmptyStray.Failure (OwnerFailure (..))
import TrashEmptyStray.FoundTrashDir (identityOf)
import TrashEmptyStray.Owner (runAsOwnerInside)

tests :: TopSpec
tests = describe "runAsOwnerInside" do
  it "見つけた時と同じディレクトリなら、その中でコマンドを実行する" do
    withRoot \root -> do
      identity <- identityOf <$> liftIO (getFileStatus root)
      runAsOwnerInside identity root "touch" ["created"]
      doesFileExist (root </> "created") >>= (`shouldBe` True)
  it "見つけた時と違うディレクトリなら、コマンドを実行せずに失敗する" do
    withRoot \root -> do
      createDirectoryIfMissing True (root </> "found")
      createDirectoryIfMissing True (root </> "replaced")
      identity <- identityOf <$> liftIO (getFileStatus (root </> "found"))
      try (runAsOwnerInside identity (root </> "replaced") "touch" ["created"])
        >>= (`shouldBe` Left ReplacedSinceFound)
      doesFileExist (root </> "replaced/created") >>= (`shouldBe` False)
  it "コマンドが失敗したら、その終了コードで失敗する" do
    withRoot \root -> do
      identity <- identityOf <$> liftIO (getFileStatus root)
      try (runAsOwnerInside identity root "false" [])
        >>= (`shouldBe` Left (ChildFailed (ExitFailure 1)))
