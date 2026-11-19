-- | mountinfoの読み取りのテスト。
module Spec.MountInfoSpec (tests) where

import Data.Text (unlines)
import Himari hiding (unlines)
import NixCachePushNcaq.Failure (ConfigFailure (..))
import NixCachePushNcaq.MountInfo (Mount (..), fileSystemOf, parseMountInfo)
import Test.Sandwich

-- | `UnparsableMountInfo`かどうか。パーサの理由の文面までは固定しない。
isUnparsable :: ConfigFailure -> Bool
isUnparsable = \case
  UnparsableMountInfo _ -> True
  _ -> False

-- | テストで使うマウントの一覧。
mounts :: [Mount]
mounts =
  [ Mount{mountPoint = "/", fileSystem = "btrfs"}
  , Mount{mountPoint = "/run", fileSystem = "tmpfs"}
  , Mount{mountPoint = "/run/user/1000", fileSystem = "tmpfs"}
  , Mount{mountPoint = "/run/media", fileSystem = "ext4"}
  ]

tests :: TopSpec
tests = describe "MountInfo" do
  describe "parseMountInfo" do
    it "任意の欄が1つの行と、複数の行と、無い行を読む" do
      parseMountInfo
        ( unlines
            [ "50 1 0:32 /@ / rw,noatime shared:1 - btrfs /dev/nvme1n1p3 rw,compress=zstd:3"
            , "69 50 0:26 / /run rw,nosuid,nodev shared:2 master:1 - tmpfs tmpfs rw,mode=755"
            , "70 50 0:27 / /proc rw,relatime - proc proc rw"
            ]
        )
        >>= ( `shouldBe`
                [ Mount{mountPoint = "/", fileSystem = "btrfs"}
                , Mount{mountPoint = "/run", fileSystem = "tmpfs"}
                , Mount{mountPoint = "/proc", fileSystem = "proc"}
                ]
            )
    it "マウントポイントの8進数のエスケープを戻す" do
      parseMountInfo "80 50 0:40 / /mnt/a\\040b\\134c rw - ext4 /dev/sda1 rw\n"
        >>= (`shouldBe` [Mount{mountPoint = "/mnt/a b\\c", fileSystem = "ext4"}])
    it "末尾の改行が無くても読む" do
      parseMountInfo "70 50 0:27 / /proc rw - proc proc rw"
        >>= (`shouldBe` [Mount{mountPoint = "/proc", fileSystem = "proc"}])
    it "空の入力は空の一覧にする" do
      parseMountInfo "" >>= (`shouldBe` [])
    it "種類の前の区切りが無い行は失敗にする" do
      parseMountInfo "70 50 0:27 / /proc rw proc proc rw\n" `shouldThrow` isUnparsable
    it "欄の足りない行は失敗にする" do
      parseMountInfo "70 50 0:27\n" `shouldThrow` isUnparsable
  describe "fileSystemOf" do
    it "パスを含む最も深いマウントの種類を返す" do
      fileSystemOf mounts "/run/user/1000/niks3" `shouldBe` Just "tmpfs"
      fileSystemOf mounts "/run/media/usb" `shouldBe` Just "ext4"
      fileSystemOf mounts "/home/ncaq" `shouldBe` Just "btrfs"
    it "マウントポイントそのものも含む" do
      fileSystemOf mounts "/run" `shouldBe` Just "tmpfs"
    it "名前が前方一致するだけの別のディレクトリは含まない" do
      fileSystemOf mounts "/running" `shouldBe` Just "btrfs"
    it "同じマウントポイントに重ねてあれば後の行を選ぶ" do
      fileSystemOf (mounts <> [Mount{mountPoint = "/run", fileSystem = "ramfs"}]) "/run/lock"
        `shouldBe` Just "ramfs"
    it "含むマウントが無ければ何も返さない" do
      fileSystemOf [Mount{mountPoint = "/run", fileSystem = "tmpfs"}] "/home" `shouldBe` Nothing
