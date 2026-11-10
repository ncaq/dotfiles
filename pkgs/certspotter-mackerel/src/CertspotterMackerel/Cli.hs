-- | コマンドライン引数の解釈と、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
--
-- 1つのコマンドに2つのサブコマンドを持つ。
--
-- * `hook`: certspotterのhookとして、通知をイベントのログへ記録する。
-- * `check`: Mackerelのチェックとして、ログに最近のイベントがあればCRITICALにする。
--
-- 書く側と読む側を1つのパッケージにまとめてあるのは、
-- ログの形式を両者が同じ型から導くようにするためである。
module CertspotterMackerel.Cli
  ( run
  , runWith
  ) where

import CertspotterMackerel.Check (check)
import CertspotterMackerel.Config (checkConfigFrom, eventLogFrom)
import CertspotterMackerel.Hook (recordNotification)
import CertspotterMackerel.Notification (notificationFrom)
import CertspotterMackerel.Status (Status (..), report, statusExitCode)
import Himari
import Options.Applicative

data Command
  = Hook
  | Check
  deriving stock (Eq, Show)

-- | コマンドライン引数を受けて、プロセスの環境変数を設定としてサブコマンドを実行する。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run argv = do
  environment <- getEnvironment
  runWith (\name -> convert <$> lookup (convert name) environment) argv

-- | 環境変数を引く関数を受け取って、サブコマンドを実行する。
--
-- `hook`は設定が揃わなければ理由をログに出して`ExitFailure 1`にする。
-- certspotterはhookが失敗した時だけ標準エラー出力を自分のログへ残す。
--
-- `check`は結果を標準出力へ出して、Mackerelの規約の終了コードで終わる。
-- 設定が揃わない時は監視そのものができていないのでUNKNOWNにする。
--
-- 引数が誤っている時は、使い方を標準エラー出力へ出して`ExitFailure 1`にする。
runWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => (Text -> Maybe Text) -> [String] -> m ()
runWith lookupVariable argv = do
  command' <- liftIO (handleParseResult (execParserPure defaultPrefs parserInfo argv))
  case command' of
    Hook -> case eventLogFrom lookupVariable of
      Right eventLog -> recordNotification eventLog (notificationFrom lookupVariable)
      Left failure -> do
        logErrorN (convert (displayException failure))
        throwM (ExitFailure 1)
    Check -> do
      status <- either (pure . unknown) check (checkConfigFrom lookupVariable)
      report status
      case statusExitCode status of
        ExitSuccess -> pure ()
        failure -> throwM failure
 where
  unknown failure = Unknown ("certspotter UNKNOWN: " <> convert (displayException failure))

parserInfo :: ParserInfo Command
parserInfo =
  info
    (commandParser <**> helper)
    (progDesc "Record certspotter events and check them for Mackerel")

commandParser :: Parser Command
commandParser =
  hsubparser
    ( command "hook" (info (pure Hook) (progDesc "Record a certspotter event as a hook"))
        <> command "check" (info (pure Check) (progDesc "Check recent events for Mackerel"))
    )
