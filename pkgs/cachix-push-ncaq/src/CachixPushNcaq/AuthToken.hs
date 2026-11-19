-- | Cachixの認証トークン。
module CachixPushNcaq.AuthToken
  ( AuthToken (..)
  , authTokenFromOutput
  ) where

import CachixPushNcaq.Failure (SecretsFailure (..))
import Data.Text (dropWhileEnd)
import Himari

-- | `Show`は中身を伏せる。
newtype AuthToken = AuthToken Text
  deriving stock (Eq)
  deriving newtype (IsString)

instance Show AuthToken where
  show _ = "AuthToken <redacted>"

-- | 復号するコマンドの標準出力からトークンを読む。末尾の改行は落とす。
--
-- 落とした結果が空なら`EmptyAuthToken`を投げる。
-- 空のトークンを渡して`cachix`の認証の失敗を待つより先に、シークレットの誤りとして知らせる。
authTokenFromOutput :: (MonadThrow m) => LazyByteString -> m AuthToken
authTokenFromOutput output = do
  let token = dropWhileEnd (\c -> c == '\n' || c == '\r') (convert output)
  when (token == mempty) (throwM EmptyAuthToken)
  pure (AuthToken token)
