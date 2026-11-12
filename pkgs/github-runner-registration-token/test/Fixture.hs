-- | テストで共有する、偽のGitHubのAPI。
module Fixture
  ( variables
  , withApi
  ) where

import Himari
import Network.HTTP.Types (hAccept, hAuthorization, hUserAgent, status201, status401)
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

-- | リポジトリごとに決まった応答を返す、偽のGitHubのAPI。
--
-- * `ncaq/dotfiles`: `AABBCC`を発行する。
-- * `ncaq/echo`: 受け取ったリクエストのメソッドとヘッダを`|`で繋いだものをトークンとして返す。
-- * `ncaq/forbidden`: 401を返す。
-- * `ncaq/garbled`: JSONではない本文を返す。
-- * その他: `token`の無いJSONを返す。
application :: Application
application request respond =
  respond case rawPathInfo request of
    "/repos/ncaq/dotfiles/actions/runners/registration-token" ->
      responseLBS status201 [] (encode Issued{token = "AABBCC"})
    "/repos/ncaq/echo/actions/runners/registration-token" ->
      responseLBS status201 [] (encode Issued{token = echo})
    "/repos/ncaq/forbidden/actions/runners/registration-token" ->
      responseLBS status401 [] "Bad credentials"
    "/repos/ncaq/garbled/actions/runners/registration-token" ->
      responseLBS status201 [] "<html>"
    _ -> responseLBS status201 [] "{}"
 where
  echo =
    convert (requestMethod request)
      <> foldMap
        (\name -> "|" <> maybe "" convert (lookup name (requestHeaders request)))
        [hAuthorization, hAccept, hUserAgent, "X-GitHub-Api-Version"]

-- | 偽のGitHubのAPIを空いているポートに立てて、そのURLを渡す。
withApi :: (MonadUnliftIO m) => (Text -> m a) -> m a
withApi action = withRunInIO \runInIO ->
  testWithApplication (pure application) \port ->
    runInIO (action ("http://127.0.0.1:" <> convert (show port)))
