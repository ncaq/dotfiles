-- | コマンドライン引数の解釈と、失敗の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
module DotfilesInstall.Cli
  ( run
  ) where

import DotfilesInstall.Failure (GitFailure, UnsupportedArchitecture)
import DotfilesInstall.Install (install)
import DotfilesInstall.Platform (detectPlatform)
import DotfilesInstall.Probe (probe)
import Himari
import Options.Applicative

-- | 今の環境を調べて、作業ディレクトリのflakeの設定を適用する。
--
-- 適用のコマンドが失敗した時は、説明はコマンド自身が既に出しているので、
-- `install`が投げる終了コードをそのまま伝える。
-- それ以外の想定している失敗は理由をログに出して`ExitFailure 1`にする。
-- 引数が誤っている時は、使い方を標準エラー出力へ出して`ExitFailure 1`にする。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run args = do
  liftIO . handleParseResult $ execParserPure defaultPrefs parserInfo args
  handle (report @UnsupportedArchitecture) . handle (report @GitFailure) $
    install "." =<< detectPlatform =<< probe
 where
  report :: forall e m a. (Exception e, MonadLogger m, MonadThrow m) => e -> m a
  report failure = do
    logErrorN (convert (displayException failure))
    throwM (ExitFailure 1)

parserInfo :: ParserInfo ()
parserInfo =
  info
    (pure () <**> helper)
    (progDesc "Apply this dotfiles configuration to the current environment")
