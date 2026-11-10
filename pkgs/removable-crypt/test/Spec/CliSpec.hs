-- | コマンドライン引数からの実行と、終了の仕方のテスト。
module Spec.CliSpec (tests) where

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
    executed plugged{controllable = False} sudo mountArguments
      >>= ( `shouldBe`
              ( Left (ExitFailure 1)
              , ["/dev/mapper/controlを操作する権限がありません。sudoを付けて実行してください"]
              , []
              )
          )
  it "呼んだ人が分からなければ、何もせずに1で終わる" do
    executed plugged [] mountArguments
      >>= ( `shouldBe`
              ( Left (ExitFailure 1)
              , ["マウントポイントの所有者にするユーザが分かりません"]
              , []
              )
          )
  it "unmountは手順を順に行って成功で終わる" do
    name <- mapperNamed "gideon"
    executed attachedBtrfs sudo ["unmount", "--name", "gideon"]
      >>= ( `shouldBe`
              ( Right ()
              , []
              ,
                [ Executed (createSnapshot name "unmount")
                , Executed (unmountFilesystem name)
                , RemovedDirectory "/mnt/gideon"
                , Executed (detach name)
                ]
              )
          )
  it "unmountで失敗した手順があれば、手順ごとに警告を出して1で終わる" do
    name <- mapperNamed "gideon"
    -- 外部コマンドは全て失敗するが、マウントポイントの削除は成功するので、その警告は出ない。
    executed attachedBtrfs{failing = const True} sudo ["unmount", "--name", "gideon"]
      >>= ( `shouldBe`
              ( Left (ExitFailure 1)
              ,
                [ "アンマウントの前のスナップショットを取れませんでした"
                , "/mnt/gideonをアンマウントできませんでした"
                , "復号を解けませんでした"
                ]
              ,
                [ Executed (createSnapshot name "unmount")
                , Executed (unmountFilesystem name)
                , RemovedDirectory "/mnt/gideon"
                , Executed (detach name)
                ]
              )
          )
  it "マウントポイントを消せなければ、その警告だけを出して1で終わる" do
    (result, logs, _) <-
      executed attachedBtrfs{undeletable = ["/mnt/gideon"]} sudo ["unmount", "--name", "gideon"]
    (result, logs) `shouldBe` (Left (ExitFailure 1), ["/mnt/gideonを消せませんでした"])
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
