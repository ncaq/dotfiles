-- | `niks3-push-ncaq`の、設定の読み取りから終了まで。
--
-- sopsで暗号化されたシークレットファイルからAPIトークンを復号して、
-- 自分のniks3サーバに`niks3 push`を実行する。
--
-- `app/niks3-push-ncaq/Main.hs`は環境を用意してここを呼ぶだけにする。
module NixCachePushNcaq.Niks3.Cli
  ( run
  , runWith
  ) where

import Data.Text.IO.Utf8 qualified
import Himari
import NixCachePushNcaq.Niks3.Command (Niks3 (..), systemNiks3)
import NixCachePushNcaq.Niks3.Config (Config (..), configFrom)
import NixCachePushNcaq.Niks3.StorePaths (storePathsFrom)
import NixCachePushNcaq.Niks3.TokenFile (systemTokenDirectory, withTokenFile)
import NixCachePushNcaq.Report (finish)
import NixCachePushNcaq.Secrets (authTokenFrom)
import NixCachePushNcaq.Signal (withTerminationAsExit)
import NixCachePushNcaq.Sops (Sops, systemSops)
import NixCachePushNcaq.Variable (processVariables)

-- | プロセスの環境変数を設定として、実際の`sops`と`niks3`で実行する。
--
-- SIGTERMやSIGHUPで止められた時にも、認証トークンの一時ファイルを消す。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run args = withTerminationAsExit do
  lookupVariable <- processVariables
  runWith
    systemSops
    systemNiks3
    systemTokenDirectory
    lookupVariable
    (liftIO Data.Text.IO.Utf8.getContents)
    args

-- | コマンドの呼び出しと、一時ファイルの置き場所を選ぶ処理と、
-- 環境変数を引く関数と、標準入力を読む処理を受け取って実行する。
--
-- 置き場所を選ぶ処理は`XDG_RUNTIME_DIR`の値を受け取る。
-- 実物はマウントの一覧を読んでtmpfsを探すので、テストでは決まった場所を返すものに替える。
--
-- 引数があれば、全て`niks3 push`の後ろへ渡す。
-- 引数が無ければ、標準入力からstoreパスを1行ずつ読んで渡す。
-- 標準入力にstoreパスが1つも無ければ、`niks3`を呼ばずに成功で終わる。
-- `niks3`はstoreパスが無いと失敗するので、渡すものが無いだけで失敗に見えるのを避ける。
-- 標準入力を読むのは、一時ファイルの置き場所を選んで認証トークンを得た後である。
-- 設定が誤っている時に入力を待たない。
--
-- 認証トークンは一時ファイルに書いて`niks3`へ渡す。
-- 置き場所は先に選ぶが、平文のファイルがある時間を短くするために、
-- ファイルを作るのは標準入力を読み終えてからにする。
--
-- 終了の仕方は`finish`に書いてある。
runWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m)
  => Sops m
  -> Niks3 m
  -> (Maybe FilePath -> m FilePath)
  -> (Text -> Maybe Text)
  -> m Text
  -> [String]
  -> m ()
runWith sops niks3 selectDirectory lookupVariable readInput args = finish do
  config <- configFrom lookupVariable
  directory <- selectDirectory config.runtimeDirectory
  token <- authTokenFrom sops "api_token" config.secretsFile
  paths <- if null args then storePathsFrom <$> readInput else pure args
  if null paths
    then ExitSuccess <$ logInfoN "標準入力にstoreパスが無いので、何も転送しません"
    else withTokenFile directory token \tokenFile ->
      niks3.push tokenFile config.serverUrl paths
