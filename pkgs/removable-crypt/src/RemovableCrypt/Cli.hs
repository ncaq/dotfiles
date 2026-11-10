-- | コマンドライン引数の解釈と、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
--
-- 1つのコマンドに2つのサブコマンドを持つ。
-- `lib/removable-crypt.nix`がデバイスごとに引数を付けて、`mnt-<名前>`と`umnt-<名前>`として包む。
--
-- lensの`argument`はoptparse-applicativeの位置引数と名前がぶつかるので、Himariの側を隠す。
module RemovableCrypt.Cli
  ( run
  , runWith
  ) where

import Himari hiding (argument)
import Options.Applicative
import RemovableCrypt.DeviceId (DeviceId, parseDeviceId)
import RemovableCrypt.Failure (Failure (..))
import RemovableCrypt.MapperName (MapperName, mountPoint, parseMapperName)
import RemovableCrypt.Mount (MountRequest (..), mount)
import RemovableCrypt.MountOption (MountOption (..))
import RemovableCrypt.System (System, realSystem)
import RemovableCrypt.Unmount (Problem (..), unmount)
import RemovableCrypt.UserName (invokingUser)

data Operation
  = Mount MapperName DeviceId [MountOption] [MountOption]
  | Unmount MapperName
  deriving stock (Eq, Show)

-- | プロセスの環境変数と実際のシステムで実行する。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run argv = do
  environment <- getEnvironment
  runWith realSystem (\name -> convert <$> lookup (convert name) environment) argv

-- | システムへの操作と環境変数を引く関数を受け取って実行する。
--
-- 失敗した時は理由をログに出して`ExitFailure 1`にする。
-- 引数が誤っている時は、使い方を標準エラー出力へ出して`ExitFailure 1`にする。
runWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m)
  => System m
  -> (Text -> Maybe Text)
  -> [String]
  -> m ()
runWith system lookupVariable argv = do
  operation <- liftIO (handleParseResult (execParserPure defaultPrefs parserInfo argv))
  handle report case operation of
    Mount name deviceId mountOptions btrfsMountOptions -> do
      owner <- maybe (throwM UnknownInvokingUser) pure (invokingUser lookupVariable)
      mount system MountRequest{name, deviceId, mountOptions, btrfsMountOptions, owner}
    Unmount name -> do
      problems <- unmount system name
      for_ problems (logWarnN . describe name)
      unless (null problems) (throwM (ExitFailure 1))
 where
  report :: (MonadLogger m, MonadThrow m) => Failure -> m a
  report failure = do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)
  describe name = \case
    SnapshotFailed -> "アンマウントの前のスナップショットを取れませんでした"
    UnmountFailed -> convert (mountPoint name) <> "をアンマウントできませんでした"
    RemoveMountPointFailed -> convert (mountPoint name) <> "を消せませんでした"
    DetachFailed -> "復号を解けませんでした"

parserInfo :: ParserInfo Operation
parserInfo =
  info
    (operationParser <**> helper)
    (progDesc "Mount and unmount an encrypted removable device")

operationParser :: Parser Operation
operationParser =
  hsubparser
    ( command "mount" (info mountParser (progDesc "Decrypt and mount the device"))
        <> command "unmount" (info (Unmount <$> nameOption) (progDesc "Unmount and lock"))
    )

mountParser :: Parser Operation
mountParser =
  Mount
    <$> nameOption
    <*> option
      (maybeReader (parseDeviceId . convert))
      (long "device-id" <> metavar "ID" <> help "Device ID under /dev/disk/by-id/")
    <*> many (mountOption "mount-option" "Mount option for every filesystem")
    <*> many (mountOption "btrfs-mount-option" "Additional mount option for btrfs")
 where
  mountOption name description =
    MountOption <$> strOption (long name <> metavar "OPTION" <> help description)

nameOption :: Parser MapperName
nameOption =
  option
    (maybeReader (parseMapperName . convert))
    (long "name" <> metavar "NAME" <> help "Device mapper name, also used as /mnt/NAME")
