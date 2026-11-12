-- | テストで共有する、偽のGitHubのAPI。
module Fixture
  ( variables
  , withApi
  , withCountedApi
  , closedApi
  ) where

import Himari
import Network.HTTP.Types
  ( hAccept
  , hAuthorization
  , hUserAgent
  , status201
  , status401
  , status503
  )
import Network.Wai (Application, rawPathInfo, requestHeaders, requestMethod, responseLBS)
import Network.Wai.Handler.Warp (testWithApplication)

-- | 連想リストを、環境変数を引く関数にする。
variables :: [(Text, Text)] -> Text -> Maybe Text
variables = flip lookup

-- | 偽のGitHubのAPIが返す、発行の応答。
newtype Issued = Issued
  { token :: Text
  }
  deriving stock (Generic)
  deriving (ToJSON) via CustomJSON '[] Issued

-- | リポジトリごとに決まった応答を返す、偽のGitHubのAPI。受け取ったリクエストを数える。
--
-- * `ncaq/dotfiles`: `AABBCC`を発行する。
-- * `ncaq/echo`: 受け取ったリクエストのメソッドとヘッダを`|`で繋いだものをトークンとして返す。
-- * `ncaq/flaky`: 最初のリクエストには503を返し、次からは`AABBCC`を発行する。
-- * `ncaq/forbidden`: 401を返す。
-- * `ncaq/garbled`: JSONではない本文を返す。
-- * その他: `token`の無いJSONを返す。
application :: IORef Int -> Application
application requests request respond = do
  count <- atomicModifyIORef' requests (\previous -> (previous + 1, previous + 1))
  respond case rawPathInfo request of
    "/repos/ncaq/dotfiles/actions/runners/registration-token" -> issued "AABBCC"
    "/repos/ncaq/echo/actions/runners/registration-token" -> issued echo
    "/repos/ncaq/flaky/actions/runners/registration-token"
      | count == 1 -> responseLBS status503 [] "Service Unavailable"
      | otherwise -> issued "AABBCC"
    "/repos/ncaq/forbidden/actions/runners/registration-token" ->
      responseLBS status401 [] "Bad credentials"
    "/repos/ncaq/garbled/actions/runners/registration-token" ->
      responseLBS status201 [] "<html>"
    _ -> responseLBS status201 [] "{}"
 where
  issued token = responseLBS status201 [] (encode Issued{token})
  echo =
    convert (requestMethod request)
      <> foldMap
        (\name -> "|" <> maybe "" convert (lookup name (requestHeaders request)))
        [hAuthorization, hAccept, hUserAgent, "X-GitHub-Api-Version"]

-- | 偽のGitHubのAPIを空いているポートに立てて、そのURLを渡す。
withApi :: (MonadUnliftIO m) => (Text -> m a) -> m a
withApi action = withCountedApi (\api _ -> action api)

-- | 誰も待ち受けていないポートを指すURL。接続は拒否される。
--
-- 偽のGitHubのAPIを立てて、止めた後のポートを使う。
closedApi :: (MonadUnliftIO m) => m Text
closedApi = withApi pure

-- | 偽のGitHubのAPIを空いているポートに立てて、そのURLと、受け取ったリクエストの数を読む操作を渡す。
withCountedApi :: (MonadUnliftIO m) => (Text -> m Int -> m a) -> m a
withCountedApi action = do
  requests <- newIORef 0
  withRunInIO \runInIO ->
    testWithApplication (pure (application requests)) \port ->
      runInIO (action ("http://127.0.0.1:" <> convert (show port)) (readIORef requests))
