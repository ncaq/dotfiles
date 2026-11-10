-- | コマンドライン引数の解釈と実行。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
--
-- NetworkManagerのdispatcherスクリプトとして、デバイスのイベントごとに呼ばれる。
-- 第1引数がインターフェース名、第2引数がアクションである。
module WifiWiredExclusive.Cli
  ( run
  , runWith
  ) where

import Himari
import WifiWiredExclusive.Action (parseAction)
import WifiWiredExclusive.Device (parseDevices)
import WifiWiredExclusive.Nmcli (Nmcli (..), systemNmcli)
import WifiWiredExclusive.Plan (plan)

-- | 実際の`nmcli`で実行する。
run :: (MonadIO m, MonadLogger m) => [String] -> m ()
run = runWith systemNmcli

-- | `nmcli`の呼び出しを受け取って実行する。
--
-- 接続状態が変化するアクションでなければ何もしない。
-- 人が呼ぶコマンドではないので、引数が足りない時も何もせず成功で終わる。
--
-- 操作はベストエフォートで行う。
-- イベントと操作の間に状態が変わって失敗することがあるが、次のイベントで再評価される。
-- 失敗は記録だけ残して残りの操作を続ける。
runWith :: (MonadLogger m) => Nmcli m -> [String] -> m ()
runWith nmcli = \case
  [_interface, action]
    | isJust (parseAction (convert action)) ->
        nmcli.listDevices >>= traverse_ attempt . plan . parseDevices
  _ -> pure ()
 where
  attempt operation =
    nmcli.perform operation >>= \case
      ExitSuccess -> pure ()
      ExitFailure code ->
        logWarnN ("操作に失敗しました(終了コード" <> convert (show code) <> "): " <> convert (show operation))
