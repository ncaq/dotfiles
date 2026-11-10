-- | マッパーの名前とデバイスのIDの検査のテスト。
--
-- ここを通った値はルートの権限でパスの一部として使われる。
module Spec.DeviceMapperNameSpec (tests) where

import Himari
import RemovableCrypt.DeviceId (devicePath, parseDeviceId)
import RemovableCrypt.DeviceMapperName (validDeviceMapperName)
import RemovableCrypt.MapperName (mapperPath, mountPoint, parseMapperName)
import Test.Sandwich

cases :: [(Text, Bool)]
cases =
  [ ("gideon", True)
  , ("two-thousand", True)
  , ("usb-JetFlash_Transcend_32GB_25XSK57XTBIHQODC-0:0-part1", True)
  , ("usb-USB_SanDisk_3.2Gen1_03005417112725151804-0:0-part1", True)
  , ("a#+-.:=@_", True)
  , ("0", True)
  , ("", False)
  , ("-leading-hyphen", False)
  , (".hidden", False)
  , ("..", False)
  , ("../etc", False)
  , ("a/b", False)
  , ("a b", False)
  , ("a\nb", False)
  , ("a$b", False)
  , ("日本語", False)
  , ("aあ", False)
  ]

tests :: TopSpec
tests = do
  describe "validDeviceMapperName" do
    for_ cases \(name, expected) ->
      it (show name <> " -> " <> show expected) do
        validDeviceMapperName name `shouldBe` expected
  describe "parseMapperName" do
    it "検査を通った名前からマウントポイントとデバイスのパスを作る" do
      (mountPoint <$> parseMapperName "gideon") `shouldBe` Just "/mnt/gideon"
      (mapperPath <$> parseMapperName "gideon") `shouldBe` Just "/dev/mapper/gideon"
    it "パスを抜け出す名前は通さない" do
      (mountPoint <$> parseMapperName "../etc") `shouldBe` Nothing
  describe "parseDeviceId" do
    it "検査を通ったIDから暗号化されたデバイスのパスを作る" do
      (devicePath <$> parseDeviceId "usb-SanDisk-0:0-part1")
        `shouldBe` Just "/dev/disk/by-id/usb-SanDisk-0:0-part1"
    it "パスを抜け出すIDは通さない" do
      (devicePath <$> parseDeviceId "../../sda") `shouldBe` Nothing
