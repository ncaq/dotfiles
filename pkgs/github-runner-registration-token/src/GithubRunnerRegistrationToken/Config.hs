-- | 起動時に受け取る設定。環境変数から受け取る。
--
-- * `GITHUB_RUNNER_REGISTRATION_TOKEN_REPOSITORY`: ランナーを登録するリポジトリ。
--   `ncaq/dotfiles`のように所有者と名前を`/`で繋いで書く。
-- * `GITHUB_RUNNER_REGISTRATION_TOKEN_API`: GitHubのAPIのURL。
--   `https://api.github.com`のようにパスを付けずに書く。
-- * `GITHUB_RUNNER_REGISTRATION_TOKEN_ACCESS_TOKEN_FILE`: 発行に使うアクセストークンが書かれたファイル。
-- * `RUNTIME_DIRECTORY`: 登録トークンを書き出すディレクトリ。systemdの`RuntimeDirectory`が設定する。
module GithubRunnerRegistrationToken.Config
  ( Config (..)
  , configFrom
  ) where

import GithubRunnerRegistrationToken.Failure (ConfigFailure (..))
import GithubRunnerRegistrationToken.Repository (Repository (..))
import Himari

data Config = Config
  { repository :: Repository
  , api :: Text
  , accessTokenFile :: FilePath
  , runtimeDirectory :: FilePath
  }
  deriving stock (Eq, Show)

-- | 環境変数を引く関数から設定を組み立てる。空は無いのと同じに扱う。
configFrom :: (Text -> Maybe Text) -> Either ConfigFailure Config
configFrom lookupVariable =
  Config . Repository
    <$> require "GITHUB_RUNNER_REGISTRATION_TOKEN_REPOSITORY"
    <*> require "GITHUB_RUNNER_REGISTRATION_TOKEN_API"
    <*> (convert <$> require "GITHUB_RUNNER_REGISTRATION_TOKEN_ACCESS_TOKEN_FILE")
    <*> (convert <$> require "RUNTIME_DIRECTORY")
 where
  require variable =
    maybe (Left (MissingVariable variable)) Right (mfilter (/= mempty) (lookupVariable variable))
