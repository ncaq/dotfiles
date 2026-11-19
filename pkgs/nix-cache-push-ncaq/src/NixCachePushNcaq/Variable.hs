-- | 設定として読む環境変数の引き方。
--
-- 環境変数を引く関数を値として受け渡すのは、テストでプロセスの環境を書き換えずに済ませるためである。
module NixCachePushNcaq.Variable
  ( processVariables
  , present
  , required
  ) where

import Himari
import NixCachePushNcaq.Failure (ConfigFailure (..))

-- | プロセスの環境変数を引く関数を作る。
processVariables :: (MonadIO m) => m (Text -> Maybe Text)
processVariables = do
  environment <- getEnvironment
  pure \name -> convert <$> lookup (convert name) environment

-- | 環境変数を引く。空は無いのと同じに扱う。
present :: (Text -> Maybe Text) -> Text -> Maybe Text
present lookupVariable = mfilter (/= mempty) . lookupVariable

-- | 環境変数を引く。無いか空なら`MissingVariable`を投げる。
required :: (MonadThrow m) => (Text -> Maybe Text) -> Text -> m Text
required lookupVariable name =
  maybe (throwM (MissingVariable name)) pure (present lookupVariable name)
