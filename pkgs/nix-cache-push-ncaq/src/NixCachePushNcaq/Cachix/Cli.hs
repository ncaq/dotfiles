-- | `cachix-push-ncaq`の、設定の読み取りから終了まで。
--
-- `secrets/cachix.yaml`から認証トークンを復号して、`cachix push ncaq`を実行する。
-- 自宅サーバのniks3キャッシュが落ちた時のフォールバックとして、
-- 別マシンやCIに手軽にキャッシュを転送するために使う。
--
-- `app/cachix-push-ncaq/Main.hs`は環境を用意してここを呼ぶだけにする。
module NixCachePushNcaq.Cachix.Cli
  ( run
  , runWith
  ) where

import Himari
import NixCachePushNcaq.Cachix.Command (Cachix (..), systemCachix)
import NixCachePushNcaq.Cachix.Config (Config (..), configFrom)
import NixCachePushNcaq.Report (finish)
import NixCachePushNcaq.Secrets (authTokenFrom)
import NixCachePushNcaq.Sops (Sops, systemSops)
import NixCachePushNcaq.Variable (processVariables)

-- | プロセスの環境変数を設定として、実際の`sops`と`cachix`で実行する。
--
-- 引数は解釈せず、全て`cachix push <cache>`の後ろへ渡す。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run args = do
  lookupVariable <- processVariables
  runWith systemSops systemCachix lookupVariable args

-- | コマンドの呼び出しと環境変数を引く関数を受け取って実行する。
--
-- 終了の仕方は`finish`に書いてある。
runWith
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m)
  => Sops m
  -> Cachix m
  -> (Text -> Maybe Text)
  -> [String]
  -> m ()
runWith sops cachix lookupVariable args = finish do
  config <- configFrom lookupVariable
  token <- authTokenFrom sops "CACHIX_AUTH_TOKEN" config.secretsFile
  cachix.push token config.cacheName args
