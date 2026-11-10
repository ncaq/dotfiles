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
--
-- 偽のシステムが投げる例外のような、`Failure`ではない例外も結果として受ける。
mountedAny :: (MonadThrow m, MonadUnliftIO m) => World -> m (Either SomeException (), [Event])
mountedAny world = do
  name <- mapperNamed "gideon"
  deviceId <- deviceWithId "usb-SanDisk-0:0-part1"
  observed world \system ->
    tryAny
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

-- | 想定している失敗で終わったものだけを結果として、マウントする。
--
-- それ以外の例外で終わった時は、その例外をそのまま投げ直す。
mounted :: (MonadThrow m, MonadUnliftIO m) => World -> m (Either Failure (), [Event])
mounted world = do
  (result, events) <- mountedAny world
  case result of
    Right () -> pure (Right (), events)
    Left exception -> case fromException exception of
      Just failure -> pure (Left failure, events)
      Nothing -> throwM exception

-- | 偽のシステムが投げた例外で終わったなら、その例外を返す。
thrown :: Either SomeException () -> Maybe FixtureFailure
thrown = either fromException (const Nothing)

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
  it "スナップショットのサブボリュームを作れなければ、アンマウントして巻き戻す" do
    name <- mapperNamed "gideon"
    (result, events) <- mounted plugged{failing = (== createSnapshotsSubvolume name)}
    result `shouldBe` Left (CommandFailed (createSnapshotsSubvolume name) (ExitFailure 1))
    drop 6 events `shouldBe` unwinding name
  it "スナップショットを取った後の掃除に失敗しても、アンマウントして巻き戻す" do
    name <- mapperNamed "gideon"
    (result, events) <- mounted plugged{failing = (== cleanupSnapshots name)}
    result `shouldBe` Left (CommandFailed (cleanupSnapshots name) (ExitFailure 1))
    drop 8 events `shouldBe` unwinding name
  describe "外部コマンドの終了コードではなく例外で失敗した時" do
    -- 実機では、呼んだ人がpasswdに無い時の所有者の変更や、ディレクトリの作成が例外を投げる。
    -- 巻き戻しが`Failure`だけを捕まえる形になっていないことを固定する。
    it "マウントポイントを作れなければ、復号を解く" do
      name <- mapperNamed "gideon"
      (result, events) <-
        mountedAny plugged{throwingOn = \_ event -> event == MadeDirectory "/mnt/gideon"}
      thrown result `shouldBe` Just (OperationThrew (MadeDirectory "/mnt/gideon"))
      -- 作れていないマウントポイントは消しに行かない。
      drop 2 events `shouldBe` [Executed (detach name)]
    it "マウントの前の所有者の変更に失敗したら、アンマウントはせずに巻き戻す" do
      name <- mapperNamed "gideon"
      (result, events) <-
        mountedAny plugged{throwingOn = firstOwning}
      thrown result `shouldBe` Just (OperationThrew owned)
      drop 3 events `shouldBe` [RemovedDirectory "/mnt/gideon", Executed (detach name)]
    it "マウントの後の所有者の変更に失敗したら、アンマウントして巻き戻す" do
      name <- mapperNamed "gideon"
      (result, events) <-
        mountedAny plugged{throwingOn = secondOwning}
      thrown result `shouldBe` Just (OperationThrew owned)
      drop 5 events `shouldBe` unwinding name
 where
  owned = GaveTo "ncaq" "/mnt/gideon"
  -- マウントの前に行う、1回目の所有者の変更。
  firstOwning previous event = event == owned && owned `notElem` previous
  -- マウントの後に行う、2回目の所有者の変更。
  secondOwning previous event = event == owned && owned `elem` previous
  -- マウントした後の失敗で行う巻き戻し。
  unwinding name =
    [ Executed (unmountFilesystem name)
    , RemovedDirectory "/mnt/gideon"
    , Executed (detach name)
    ]
