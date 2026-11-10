-- | コマンドライン引数からの実行と、終了の仕方のテスト。
module Spec.CliSpec (tests) where

import Data.Text (isInfixOf)
import Fixture
import Himari
import RemovableCrypt.Cli (runWith)
import RemovableCrypt.Command
import Test.Sandwich

-- | ログを端末へ出さずに集めて実行し、結果とログと行われた操作を返す。
executed
  :: (MonadIO m) => World -> [(Text, Text)] -> [String] -> m (Either ExitCode (), [Text], [Event])
executed world environment argv = do
  logs <- newIORef []
  (result, events) <-
    runSimpleEnvWith
      (\_ _ _ message -> modifyIORef' logs (<> [convert (fromLogStr message)]))
      (observed world \system -> try (runWith system (`lookup` environment) argv))
  (result,,events) <$> readIORef logs

mountArguments :: [String]
mountArguments =
  [ "mount"
  , "--name"
  , "gideon"
  , "--device-id"
  , "usb-SanDisk-0:0-part1"
  , "--mount-options"
  , "noatime,nodiratime"
  , "--btrfs-mount-options"
  , "compress=zstd"
  ]

sudo :: [(Text, Text)]
sudo = [("SUDO_USER", "ncaq"), ("USER", "root")]

-- | まだ復号されていないデバイスが挿さっている状態。
plugged :: World
plugged = attachedBtrfs{paths = ["/dev/disk/by-id/usb-SanDisk-0:0-part1"]}

tests :: TopSpec
tests = describe "runWith" do
  it "mountは引数のオプションでマウントして、sudoを呼んだ人を所有者にする" do
    name <- mapperNamed "gideon"
    (result, logs, events) <- executed plugged sudo mountArguments
    (result, logs) `shouldBe` (Right (), [])
    filter (== Executed (mountFilesystem name ["noatime", "nodiratime", "compress=zstd"])) events
      `shouldNotBe` []
    filter (== GaveTo "ncaq" "/mnt/gideon") events `shouldNotBe` []
  it "mountが失敗したら理由を出して1で終わる" do
    (result, logs, _) <- executed plugged{controllable = False} sudo mountArguments
    result `shouldBe` Left (ExitFailure 1)
    length logs `shouldBe` 1
    filter (isInfixOf "sudo") logs `shouldBe` logs
  it "呼んだ人が分からなければ、何もせずに1で終わる" do
    (result, logs, events) <- executed plugged [] mountArguments
    result `shouldBe` Left (ExitFailure 1)
    length logs `shouldBe` 1
    events `shouldBe` []
  it "unmountは成功で終わる" do
    (result, logs, events) <- executed attachedBtrfs sudo ["unmount", "--name", "gideon"]
    (result, logs) `shouldBe` (Right (), [])
    length events `shouldBe` 4
  it "unmountで失敗した手順があれば、手順ごとに警告を出して1で終わる" do
    (result, logs, _) <-
      executed attachedBtrfs{failing = const True} sudo ["unmount", "--name", "gideon"]
    result `shouldBe` Left (ExitFailure 1)
    length logs `shouldBe` 3
  for_
    [ mountArguments <> ["--mount-options", "suid,dev"]
    , mountArguments <> ["--btrfs-mount-options", "suid"]
    , mountArguments <> ["--name", "other"]
    , ["mount", "--name", "gideon", "--device-id", "usb-SanDisk-0:0-part1"]
    , ["mount", "--name", "../etc", "--device-id", "usb-SanDisk-0:0-part1"]
    , ["mount", "--name", "gideon", "--device-id", "../../sda"]
    , ["mount", "--name", "gideon"]
    , ["unmount", "--name", "a/b"]
    , ["unmount"]
    , []
    ]
    \argv ->
      it ("引数が" <> show argv <> "なら、何もせずに1で終わる") do
        -- 使い方はoptparse-applicativeが標準エラー出力へ直接出すので、こちらのログには何も出ない。
        executed plugged sudo argv >>= (`shouldBe` (Left (ExitFailure 1), [], []))
