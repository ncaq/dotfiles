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

import Himari
import NixCachePushNcaq.Niks3.Command (Niks3 (..), systemNiks3)
import NixCachePushNcaq.Niks3.Config (Config (..), configFrom)
import NixCachePushNcaq.Niks3.StorePaths (storePathsFrom)
import NixCachePushNcaq.Niks3.TokenFile (withTokenFile)
import NixCachePushNcaq.Report (finish)
import NixCachePushNcaq.Secrets (authTokenFrom)
import NixCachePushNcaq.Signal (exitOnTermination)
import NixCachePushNcaq.Sops (Sops, systemSops)
import NixCachePushNcaq.Variable (processVariables)

-- | プロセスの環境変数を設定として、実際の`sops`と`niks3`で実行する。
--
-- SIGTERMやSIGHUPで止められた時にも、認証トークンの一時ファイルを消す。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run args = do
  exitOnTermination
  lookupVariable <- processVariables
  runWith systemSops systemNiks3 lookupVariable (liftIO getContents) args

-- | コマンドの呼び出しと環境変数を引く関数と、標準入力を読む処理を受け取って実行する。
--
-- 引数があれば、全て`niks3 push`の後ろへ渡す。
-- 引数が無ければ、標準入力からstoreパスを1行ずつ読んで渡す。
-- 標準入力を読むのは認証トークンを得た後なので、設定が誤っている時に入力を待たない。
--
-- 認証トークンは一時ファイルに書いて`niks3`へ渡す。
-- 平文のファイルがある時間を短くするために、標準入力を読み終えてから作る。
--
-- 終了の仕方は`finish`に書いてある。
runWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m)
  => Sops m
  -> Niks3 m
  -> (Text -> Maybe Text)
  -> m String
  -> [String]
  -> m ()
runWith sops niks3 lookupVariable readInput args = finish do
  config <- configFrom lookupVariable
  token <- authTokenFrom sops "api_token" config.secretsFile
  paths <- if null args then storePathsFrom <$> readInput else pure args
  directory <- maybe getTemporaryDirectory pure config.runtimeDirectory
  withTokenFile directory token \tokenFile ->
    niks3.push tokenFile config.serverUrl paths
