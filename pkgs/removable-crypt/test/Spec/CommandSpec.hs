-- | 呼び出す外部コマンドの引数のテスト。
module Spec.CommandSpec (tests) where

import Fixture
import RemovableCrypt.Command
import RemovableCrypt.FilesystemType (FilesystemType (..), parseFilesystemType)
import RemovableCrypt.MountOption (joinMountOptions, splitMountOptions)
import Test.Sandwich

tests :: TopSpec
tests = do
  describe "Command" do
    it "デバイスを復号してマッパーの名前を付ける" do
      name <- mapperNamed "gideon"
      deviceId <- deviceWithId "usb-SanDisk-0:0-part1"
      attach name deviceId
        `shouldBe` Command
          "systemd-cryptsetup"
          ["attach", "gideon", "/dev/disk/by-id/usb-SanDisk-0:0-part1"]
    it "復号を解く" do
      name <- mapperNamed "gideon"
      detach name `shouldBe` Command "systemd-cryptsetup" ["detach", "gideon"]
    it "マウントオプションをカンマで繋いでマウントする" do
      name <- mapperNamed "gideon"
      mountFilesystem name ["noatime", "compress=zstd"]
        `shouldBe` Command
          "mount"
          ["-o", "noatime,compress=zstd", "/dev/mapper/gideon", "/mnt/gideon"]
    it "マウントポイントを指定してアンマウントする" do
      name <- mapperNamed "gideon"
      unmountFilesystem name `shouldBe` Command "umount" ["/mnt/gideon"]
    it "スナップショットを置くサブボリュームを作る" do
      name <- mapperNamed "gideon"
      createSnapshotsSubvolume name
        `shouldBe` Command "btrfs" ["subvolume", "create", "/mnt/gideon/.snapshots"]
    it "説明を付けて、timelineで掃除される対象としてスナップショットを取る" do
      name <- mapperNamed "gideon"
      createSnapshot name "mount"
        `shouldBe` Command
          "snapper"
          ["-c", "gideon", "create", "--cleanup-algorithm", "timeline", "--description", "mount"]
    it "timelineの規則で掃除する" do
      name <- mapperNamed "gideon"
      cleanupSnapshots name `shouldBe` Command "snapper" ["-c", "gideon", "cleanup", "timeline"]
  describe "joinMountOptions" do
    it "1つならそのまま" do
      joinMountOptions ["noatime"] `shouldBe` "noatime"
    it "無ければ空" do
      joinMountOptions [] `shouldBe` ""
  describe "parseFilesystemType" do
    it "btrfsを読む" do
      parseFilesystemType "btrfs\n" `shouldBe` Btrfs
    it "他の種類はそのまま持つ" do
      parseFilesystemType "ext4\n" `shouldBe` OtherFilesystem "ext4"
  describe "splitMountOptions" do
    it "カンマで分ける" do
      splitMountOptions "noatime,compress=zstd" `shouldBe` ["noatime", "compress=zstd"]
    it "空文字列はオプションが無いものとして読む" do
      splitMountOptions "" `shouldBe` []
    it "空の要素は捨てる" do
      splitMountOptions "noatime,,compress=zstd," `shouldBe` ["noatime", "compress=zstd"]
