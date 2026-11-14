-- | 設定の適用。
module DotfilesInstall.Install
  ( install
  , installWith
  ) where

import DotfilesInstall.LastCommit.Stage (withStagedLastCommit)
import DotfilesInstall.Platform (Platform (..))
import DotfilesInstall.SwitchCommand (SwitchCommand (..), commandLine, switchCommand)
import Himari

-- | 指定のリポジトリのflakeの設定を、環境の種類に合ったコマンドで適用する。
--
-- NixOSではブートエントリのラベルに使うコミットの情報を、適用の間だけ注入する。
-- 適用のコマンドが失敗した時は、その終了コードを例外として投げる。
install
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => FilePath -> Platform -> m ()
install repository = installWith (execute repository) repository

-- | `install`の、適用のコマンドの走らせ方を外から渡す形。
--
-- 環境の種類ごとに注入するかどうかの分岐を、実際のコマンドを走らせずにテストするためにある。
installWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m)
  => (SwitchCommand -> m a)
  -> FilePath
  -> Platform
  -> m a
installWith run repository platform = case platform of
  NixOS _ -> withStagedLastCommit repository switch
  NixOnDroid -> switch
  HomeManager _ -> switch
 where
  switch = run (switchCommand platform)

-- | 適用のコマンドを指定のリポジトリで走らせる。失敗したら終了コードを例外として投げる。
execute :: (MonadIO m, MonadLogger m, MonadThrow m) => FilePath -> SwitchCommand -> m ()
execute repository command = do
  logInfoN ("設定を適用します: " <> commandLine command)
  code <-
    runProcess . setWorkingDir repository $
      proc (convert command.program) (convert <$> command.arguments)
  unless (code == ExitSuccess) (throwM code)
