-- | 起動時に受け取る設定。環境変数から受け取る。
--
-- * `GARAGE_SETUP_NAME`: バケットのグローバルエイリアス。
--   キーの名前と、キーファイルを渡すユーザとグループの名前も兼ねる。
--   この名前のユーザとグループがホストに無いと、キーファイルの所有者を変えるところで失敗する。
-- * `GARAGE_SETUP_API`: GarageのAdmin APIのURL。`http://192.0.2.1:3903`のようにパスを付けずに書く。
-- * `GARAGE_SETUP_ADMIN_TOKEN_FILE`: Admin APIのトークンが書かれたファイル。
-- * `RUNTIME_DIRECTORY`: キーファイルを書き出すディレクトリ。systemdの`RuntimeDirectory`が設定する。
module GarageSetup.Config
  ( Config (..)
  , configFrom
  ) where

import GarageSetup.BucketName (BucketName (..))
import GarageSetup.Failure (ConfigFailure (..))
import Himari

data Config = Config
  { name :: BucketName
  , api :: Text
  , adminTokenFile :: FilePath
  , runtimeDirectory :: FilePath
  }
  deriving stock (Eq, Show)

-- | 環境変数を引く関数から設定を組み立てる。空は無いのと同じに扱う。
configFrom :: (Text -> Maybe Text) -> Either ConfigFailure Config
configFrom lookupVariable =
  Config
    <$> name
    <*> require "GARAGE_SETUP_API"
    <*> (convert <$> require "GARAGE_SETUP_ADMIN_TOKEN_FILE")
    <*> (convert <$> require "RUNTIME_DIRECTORY")
 where
  name = BucketName <$> require "GARAGE_SETUP_NAME"
  require variable =
    maybe (Left (MissingVariable variable)) Right (mfilter (/= mempty) (lookupVariable variable))
