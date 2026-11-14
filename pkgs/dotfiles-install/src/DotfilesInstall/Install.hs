-- | 設定の適用。
module DotfilesInstall.Install
  ( install
  ) where

import DotfilesInstall.LastCommit.Stage (withStagedLastCommit)
import DotfilesInstall.Platform (Platform (..))
import DotfilesInstall.SwitchCommand (SwitchCommand (..), commandLine, switchCommand)
import Himari

-- | 指定のリポジトリのflakeの設定を、環境の種類に合ったコマンドで適用する。
--
-- NixOSではブートエントリのラベルに使うコミットの情報を、適用の間だけ注入する。
-- 適用のコマンドの終了コードをそのまま返す。
install
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => FilePath -> Platform -> m ExitCode
install repository platform = case platform of
  NixOS _ -> withStagedLastCommit repository switch
  NixOnDroid -> switch
  HomeManager _ -> switch
 where
  command = switchCommand platform
  switch = do
    logInfoN ("設定を適用します: " <> commandLine command)
    runProcess (setWorkingDir repository (proc command.program command.arguments))
