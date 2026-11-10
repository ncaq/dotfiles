-- | マウントの手順と、失敗した時の巻き戻しのテスト。
--
-- 実機で確かめるにはデバイスを挿してルートで動かす必要があり、
-- 途中の手順の失敗は狙って起こせない。
-- 手順の並びと巻き戻しの範囲をここで固定する。
module Spec.MountSpec (tests) where

import Fixture
import Himari
import RemovableCrypt.Command
import RemovableCrypt.Failure (Failure (..))
import RemovableCrypt.FilesystemType (FilesystemType (..))
import RemovableCrypt.Mount (MountRequest (..), mount)
import Test.Sandwich

-- | まだ復号されていないデバイスが挿さっている状態。
plugged :: World
plugged = attachedBtrfs{paths = ["/dev/disk/by-id/usb-SanDisk-0:0-part1"]}

-- | マウントして、結果と、行われた操作を順に返す。
mounted :: (MonadThrow m, MonadUnliftIO m) => World -> m (Either Failure (), [Event])
mounted world = do
  name <- mapperNamed "gideon"
  deviceId <- deviceWithId "usb-SanDisk-0:0-part1"
  observed world \system ->
    try
      ( mount
          system
          MountRequest
            { name
            , deviceId
            , mountOptions = ["noatime"]
            , btrfsMountOptions = ["compress=zstd"]
            , owner = "ncaq"
            }
      )

-- | 指定のプログラムと最初の引数のコマンドを失敗させる。
failingAt :: String -> String -> World -> World
failingAt program firstArgument world =
  world
    { failing = \command ->
        command.program == program && take 1 command.arguments == [firstArgument]
    }

tests :: TopSpec
tests = describe "mount" do
  it "btrfsなら、マウントしてからスナップショットを取って掃除する" do
    name <- mapperNamed "gideon"
    deviceId <- deviceWithId "usb-SanDisk-0:0-part1"
    mounted plugged
      >>= ( `shouldBe`
              ( Right ()
              ,
                [ Executed (attach name deviceId)
                , MadeDirectory "/mnt/gideon"
                , GaveTo "ncaq" "/mnt/gideon"
                , Executed (mountFilesystem name ["noatime", "compress=zstd"])
                , GaveTo "ncaq" "/mnt/gideon"
                , Executed (createSnapshotsSubvolume name)
                , Executed (createSnapshot name "mount")
                , Executed (cleanupSnapshots name)
                ]
              )
          )
  it "スナップショットのサブボリュームが既にあれば作らない" do
    name <- mapperNamed "gideon"
    (result, events) <- mounted plugged{paths = plugged.paths <> ["/mnt/gideon/.snapshots"]}
    result `shouldBe` Right ()
    filter (== Executed (createSnapshotsSubvolume name)) events `shouldBe` []
    drop 5 events
      `shouldBe` [Executed (createSnapshot name "mount"), Executed (cleanupSnapshots name)]
  it "btrfsでなければ、btrfs用のオプションを付けず、スナップショットも取らない" do
    name <- mapperNamed "gideon"
    (result, events) <- mounted plugged{filesystem = Just (OtherFilesystem "ext4")}
    result `shouldBe` Right ()
    drop 3 events
      `shouldBe` [Executed (mountFilesystem name ["noatime"]), GaveTo "ncaq" "/mnt/gideon"]
  it "権限が無ければ何もしない" do
    mounted plugged{controllable = False} >>= (`shouldBe` (Left NoPermission, []))
  it "デバイスが挿さっていなければ何もしない" do
    mounted plugged{paths = []}
      >>= (`shouldBe` (Left (DeviceNotFound "/dev/disk/by-id/usb-SanDisk-0:0-part1"), []))
  it "復号に失敗したら、何も片付けずに失敗する" do
    name <- mapperNamed "gideon"
    deviceId <- deviceWithId "usb-SanDisk-0:0-part1"
    mounted (failingAt "systemd-cryptsetup" "attach" plugged)
      >>= ( `shouldBe`
              ( Left (CommandFailed (attach name deviceId) (ExitFailure 1))
              , [Executed (attach name deviceId)]
              )
          )
  it "ファイルシステムの種類を調べられなければ、マウントポイントを消して復号を解く" do
    name <- mapperNamed "gideon"
    (result, events) <- mounted plugged{filesystem = Nothing}
    result `shouldBe` Left (UnknownFilesystem "/dev/mapper/gideon")
    drop 3 events `shouldBe` [RemovedDirectory "/mnt/gideon", Executed (detach name)]
  it "マウントに失敗したら、アンマウントはせずに、マウントポイントを消して復号を解く" do
    name <- mapperNamed "gideon"
    (result, events) <- mounted (failingAt "mount" "-o" plugged)
    result
      `shouldBe` Left
        (CommandFailed (mountFilesystem name ["noatime", "compress=zstd"]) (ExitFailure 1))
    drop 4 events `shouldBe` [RemovedDirectory "/mnt/gideon", Executed (detach name)]
  it "スナップショットに失敗したら、アンマウントしてからマウントポイントを消して復号を解く" do
    name <- mapperNamed "gideon"
    (result, events) <- mounted (failingAt "snapper" "-c" plugged)
    result `shouldBe` Left (CommandFailed (createSnapshot name "mount") (ExitFailure 1))
    drop 7 events
      `shouldBe` [ Executed (unmountFilesystem name)
                 , RemovedDirectory "/mnt/gideon"
                 , Executed (detach name)
                 ]
  it "片付けの中でマウントポイントを消せなくても、復号は解いて元の失敗を伝える" do
    name <- mapperNamed "gideon"
    (result, events) <- mounted (failingAt "mount" "-o" plugged){undeletable = ["/mnt/gideon"]}
    result
      `shouldBe` Left
        (CommandFailed (mountFilesystem name ["noatime", "compress=zstd"]) (ExitFailure 1))
    drop 4 events `shouldBe` [RemovedDirectory "/mnt/gideon", Executed (detach name)]
