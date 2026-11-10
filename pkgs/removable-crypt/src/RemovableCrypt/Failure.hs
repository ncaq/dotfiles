-- | 想定している失敗の型。
module RemovableCrypt.Failure
  ( Failure (..)
  ) where

import Himari
import RemovableCrypt.Command (Command (..))

data Failure
  = -- | device-mapperを操作する権限が無い。
    NoPermission
  | -- | 暗号化されたデバイスが見つからない。そのパス。
    DeviceNotFound FilePath
  | -- | 復号したデバイスの中のファイルシステムの種類を調べられなかった。そのパス。
    UnknownFilesystem FilePath
  | -- | コマンドを呼んだ人が分からない。
    UnknownInvokingUser
  | -- | 外部コマンドが失敗した。説明はコマンド自身が既に出している。
    CommandFailed Command ExitCode
  deriving stock (Eq, Show)

instance Exception Failure where
  displayException = \case
    NoPermission -> "/dev/mapper/controlを操作する権限がありません。sudoを付けて実行してください"
    DeviceNotFound path -> "デバイスが見つかりません: " <> path
    UnknownFilesystem path -> "ファイルシステムの種類を調べられません: " <> path
    UnknownInvokingUser -> "マウントポイントの所有者にするユーザが分かりません"
    CommandFailed command code ->
      unwords (command.program : command.arguments) <> "が" <> show code <> "で失敗しました"
