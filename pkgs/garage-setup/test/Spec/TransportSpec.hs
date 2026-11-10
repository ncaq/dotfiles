-- | Admin APIへのHTTPでの送信のテスト。
--
-- 偽のサーバを空いているポートに立てて、実際にHTTPで送る。
module Spec.TransportSpec (tests) where

import GarageSetup.Call (Call (..), Method (..))
import GarageSetup.Failure (ApiFailure (..))
import GarageSetup.Transport (Transport, httpTransport)
import Himari
import Network.HTTP.Types (hAuthorization, status200, status204, status404)
import Network.Wai
  ( Application
  , rawPathInfo
  , rawQueryString
  , requestHeaders
  , requestMethod
  , responseLBS
  , strictRequestBody
  )
import Network.Wai.Handler.Warp (testWithApplication)
import Test.Sandwich

-- | 偽のAdmin APIが受け取ったリクエストの中身。
data Echo = Echo
  { method :: Text
  , query :: Text
  , authorization :: Maybe Text
  , body :: Maybe Value
  }
  deriving stock (Generic)
  deriving (ToJSON) via CustomJSON '[] Echo

-- | パスごとに決まった応答を返す、偽のAdmin API。
--
-- `/echo`は受け取ったリクエストの中身をJSONにして返す。
application :: Application
application request respond = do
  content <- strictRequestBody request
  respond case rawPathInfo request of
    "/echo" ->
      responseLBS
        status200
        []
        ( encode
            Echo
              { method = convert (requestMethod request)
              , query = convert (rawQueryString request)
              , authorization = convert <$> lookup hAuthorization (requestHeaders request)
              , body = eitherDecode content ^? _Right
              }
        )
    "/empty" -> responseLBS status204 [] mempty
    "/garbled" -> responseLBS status200 [] "<html>"
    _ -> responseLBS status404 [] "{}"

-- | 偽のAdmin APIへ繋ぐ送信を渡す。
withServer :: (MonadThrow m, MonadUnliftIO m) => (Transport m -> m a) -> m a
withServer action = withRunInIO \runInIO ->
  testWithApplication (pure application) \port ->
    runInIO (action (httpTransport ("http://127.0.0.1:" <> convert (show port)) "admin-token"))

tests :: TopSpec
tests = describe "httpTransport" do
  it "メソッドとクエリ文字列とBearerのトークンを付けて送る" do
    response <-
      withServer \transport ->
        transport
          Call
            { method = Get
            , path = "/echo"
            , query = [("globalAlias", "nix-cache"), ("id", "0123abcd")]
            , body = Nothing
            }
    response
      `shouldBe` [aesonQQ|{
        "method": "GET",
        "query": "?globalAlias=nix-cache&id=0123abcd",
        "authorization": "Bearer admin-token",
        "body": null
      }|]
  it "本文をJSONとして送る" do
    response <-
      withServer \transport ->
        transport
          Call
            { method = Post
            , path = "/echo"
            , query = []
            , body = Just [aesonQQ|{"globalAlias": "nix-cache"}|]
            }
    response
      `shouldBe` [aesonQQ|{
        "method": "POST",
        "query": "",
        "authorization": "Bearer admin-token",
        "body": {"globalAlias": "nix-cache"}
      }|]
  it "本文の無い成功はnullとして返す" do
    response <-
      withServer \transport ->
        transport Call{method = Post, path = "/empty", query = [], body = Nothing}
    response `shouldBe` Null
  it "成功ではない状態コードは、パスと状態コードを持つ失敗にする" do
    withServer
      ( \transport ->
          transport Call{method = Get, path = "/missing", query = [], body = Nothing}
      )
      `shouldThrow` (== UnexpectedStatus "/missing" 404)
  it "JSONとして読めない本文は、パスを持つ失敗にする" do
    withServer
      ( \transport ->
          transport Call{method = Get, path = "/garbled", query = [], body = Nothing}
      )
      `shouldThrow` \case
        UndecodableBody path _ -> path == "/garbled"
        _ -> False
