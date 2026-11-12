-- | 登録トークンを発行するためのGitHubのアクセストークン。
--
-- リポジトリの`Administration: Read and write`を持つfine-grained PATを想定している。
module GithubRunnerRegistrationToken.AccessToken
  ( AccessToken (..)
  , readAccessToken
  ) where

import Data.ByteString qualified as B
import Data.Text qualified as T
import GithubRunnerRegistrationToken.Failure (ConfigFailure (..))
import Himari

-- | `Show`は中身を伏せる。
newtype AccessToken = AccessToken Text
  deriving stock (Eq)
  deriving newtype (IsString)

instance Show AccessToken where
  show _ = "AccessToken <redacted>"

-- | ファイルからトークンを読む。前後の空白と改行は落とす。
--
-- 落とした結果が空なら`EmptyAccessToken`を投げる。
-- 空のトークンを送って401を待つより先に、設定の誤りとして知らせる。
readAccessToken :: (MonadIO m, MonadThrow m) => FilePath -> m AccessToken
readAccessToken path = do
  token <- T.strip . convert <$> liftIO (B.readFile path)
  when (token == mempty) (throwM (EmptyAccessToken path))
  pure (AccessToken token)
