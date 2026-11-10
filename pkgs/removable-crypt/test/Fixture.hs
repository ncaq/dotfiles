-- | 実際のデバイスを触らずに済ませるための、偽のシステム。
module Fixture
  ( Event (..)
  , FixtureFailure (..)
  , World (..)
  , attachedBtrfs
  , observed
  , mapperNamed
  , deviceWithId
  ) where

import Himari
import RemovableCrypt.Command (Command (..))
import RemovableCrypt.DeviceId (DeviceId, parseDeviceId)
import RemovableCrypt.FilesystemType (FilesystemType (..))
import RemovableCrypt.MapperName (MapperName, parseMapperName)
import RemovableCrypt.System (System (..))
import RemovableCrypt.UserName (UserName)

-- | 偽のシステムが投げる失敗。
data FixtureFailure
  = -- | 消せないことにしてあるディレクトリを消そうとした。
    DirectoryNotRemovable FilePath
  | -- | 例外を投げることにしてある操作が行われた。
    OperationThrew Event
  | -- | テストの中の名前が検査を通らなかった。
    InvalidName Text
  deriving stock (Eq, Show)

instance Exception FixtureFailure

-- | 偽のシステムへ行われた操作。
data Event
  = Executed Command
  | MadeDirectory FilePath
  | RemovedDirectory FilePath
  | GaveTo UserName FilePath
  deriving stock (Eq, Show)

-- | 偽のシステムの状態と振る舞い。
data World = World
  { controllable :: Bool
  , paths :: [FilePath]
  -- ^ 存在するパス。ディレクトリも含む。
  , filesystem :: Maybe FilesystemType
  , failing :: Command -> Bool
  -- ^ 失敗させる外部コマンド。
  , undeletable :: [FilePath]
  -- ^ 消そうとすると失敗するディレクトリ。
  , throwingOn :: [Event] -> Event -> Bool
  -- ^ 例外を投げさせる操作。それまでに行われた操作と、今の操作を受け取る。
  -- ディレクトリの作成と所有者の変更にだけ効く。
  }

-- | `gideon`が復号されてbtrfsとして`/mnt/gideon`にマウントされている状態。
attachedBtrfs :: World
attachedBtrfs =
  World
    { controllable = True
    , paths =
        [ "/dev/disk/by-id/usb-SanDisk-0:0-part1"
        , "/dev/mapper/gideon"
        , "/mnt/gideon"
        , "/mnt/gideon/.snapshots"
        ]
    , filesystem = Just Btrfs
    , failing = const False
    , undeletable = []
    , throwingOn = \_ _ -> False
    }

-- | 偽のシステムで操作を行って、結果と、行われた操作を順に返す。
--
-- ディレクトリを作る操作と消す操作は、存在するパスの集合へ反映する。
observed
  :: (MonadThrow m, MonadUnliftIO m) => World -> (System m -> m a) -> m (a, [Event])
observed world action = do
  events <- newIORef []
  existing <- newIORef world.paths
  let record event = modifyIORef' events (<> [event])
      -- 記録してから、例外を投げることにしてある操作なら投げる。
      perform event = do
        previous <- readIORef events
        record event
        when (world.throwingOn previous event) (throwM (OperationThrew event))
      system =
        System
          { mapperControllable = pure world.controllable
          , pathExists = \path -> elem path <$> readIORef existing
          , directoryExists = \path -> elem path <$> readIORef existing
          , makeDirectory = \path -> do
              perform (MadeDirectory path)
              modifyIORef' existing (<> [path])
          , removeEmptyDirectory = \path -> do
              record (RemovedDirectory path)
              when (path `elem` world.undeletable) (throwM (DirectoryNotRemovable path))
              modifyIORef' existing (filter (/= path))
          , giveTo = \user path -> perform (GaveTo user path)
          , filesystemType = const (pure world.filesystem)
          , execute = \command -> do
              record (Executed command)
              pure (if world.failing command then ExitFailure 1 else ExitSuccess)
          }
  result <- action system
  (result,) <$> readIORef events

-- | テスト用の名前を検査済みの型にする。検査を通らなければ例外で落とす。
mapperNamed :: (MonadThrow m) => Text -> m MapperName
mapperNamed name = maybe (throwM (InvalidName name)) pure (parseMapperName name)

-- | テスト用のIDを検査済みの型にする。検査を通らなければ例外で落とす。
deviceWithId :: (MonadThrow m) => Text -> m DeviceId
deviceWithId deviceId = maybe (throwM (InvalidName deviceId)) pure (parseDeviceId deviceId)
