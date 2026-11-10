-- | アンマウントの手順と、失敗しても残りを続けることのテスト。
module Spec.UnmountSpec (tests) where

import Fixture
import Himari
import RemovableCrypt.Command
import RemovableCrypt.Failure (Failure (..))
import RemovableCrypt.FilesystemType (FilesystemType (..))
import RemovableCrypt.Unmount (Problem (..), unmount)
import Test.Sandwich

-- | アンマウントして、結果と、行われた操作を順に返す。
unmounted
  :: (MonadThrow m, MonadUnliftIO m) => World -> m (Either Failure [Problem], [Event])
unmounted world = do
  name <- mapperNamed "gideon"
  observed world \system -> try (unmount system name)

-- | 指定のプログラムのコマンドを失敗させる。
failingProgram :: String -> World -> World
failingProgram program world = world{failing = \command -> command.program == program}

tests :: TopSpec
tests = describe "unmount" do
  it "btrfsなら、スナップショットを取ってからアンマウントして、復号を解く" do
    name <- mapperNamed "gideon"
    unmounted attachedBtrfs
      >>= ( `shouldBe`
              ( Right []
              ,
                [ Executed (createSnapshot name "unmount")
                , Executed (unmountFilesystem name)
                , RemovedDirectory "/mnt/gideon"
                , Executed (detach name)
                ]
              )
          )
  it "btrfsでなければ、スナップショットは取らない" do
    name <- mapperNamed "gideon"
    unmounted attachedBtrfs{filesystem = Just (OtherFilesystem "ext4")}
      >>= ( `shouldBe`
              ( Right []
              ,
                [ Executed (unmountFilesystem name)
                , RemovedDirectory "/mnt/gideon"
                , Executed (detach name)
                ]
              )
          )
  it "ファイルシステムの種類を調べられなくても、スナップショットを飛ばして続ける" do
    (result, events) <- unmounted attachedBtrfs{filesystem = Nothing}
    result `shouldBe` Right []
    length events `shouldBe` 3
  it "スナップショットに失敗しても、残りの手順を続けて失敗を返す" do
    (result, events) <- unmounted (failingProgram "snapper" attachedBtrfs)
    result `shouldBe` Right [SnapshotFailed]
    length events `shouldBe` 4
  it "アンマウントに失敗しても、残りの手順を続けて失敗を返す" do
    (result, events) <- unmounted (failingProgram "umount" attachedBtrfs)
    result `shouldBe` Right [UnmountFailed]
    length events `shouldBe` 4
  it "マウントポイントを消せなくても、復号は解いて失敗を返す" do
    name <- mapperNamed "gideon"
    (result, events) <- unmounted attachedBtrfs{undeletable = ["/mnt/gideon"]}
    result `shouldBe` Right [RemoveMountPointFailed]
    drop 3 events `shouldBe` [Executed (detach name)]
  it "復号を解けなければ失敗を返す" do
    (result, _) <- unmounted (failingProgram "systemd-cryptsetup" attachedBtrfs)
    result `shouldBe` Right [DetachFailed]
  it "複数の手順が失敗したら全て返す" do
    (result, _) <- unmounted attachedBtrfs{failing = const True, undeletable = ["/mnt/gideon"]}
    result `shouldBe` Right [SnapshotFailed, UnmountFailed, RemoveMountPointFailed, DetachFailed]
  it "既に復号が解かれていれば、アンマウントだけを試みる" do
    name <- mapperNamed "gideon"
    unmounted attachedBtrfs{paths = [], failing = const True}
      >>= (`shouldBe` (Right [UnmountFailed], [Executed (unmountFilesystem name)]))
  it "権限が無ければ何もしない" do
    unmounted attachedBtrfs{controllable = False} >>= (`shouldBe` (Left NoPermission, []))
