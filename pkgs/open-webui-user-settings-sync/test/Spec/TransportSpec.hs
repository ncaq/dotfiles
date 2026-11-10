-- | Open WebUIへのHTTPでの送信のテスト。
--
-- 偽のサーバを空いているポートに立てて、実際にHTTPで送る。
module Spec.TransportSpec (tests) where

import Himari
import Network.HTTP.Types (hAuthorization, status200, status404)
import Network.Wai
  ( Application
  , rawPathInfo
  , requestHeaders
  , requestMethod
  , responseLBS
  , strictRequestBody
  )
import Network.Wai.Handler.Warp (testWithApplication)
import Test.Sandwich
import UserSettingsSync.Call (Call (..), Method (..))
import UserSettingsSync.Failure (ApiFailure (..))
import UserSettingsSync.Transport (Transport, httpTransport)

-- | 偽のOpen WebUIが受け取ったリクエストの中身。
data Echo = Echo
  { method :: Text
  , authorization :: Maybe Text
  , body :: Maybe Value
  }
  deriving stock (Generic)
  deriving (ToJSON) via CustomJSON '[] Echo

-- | パスごとに決まった応答を返す、偽のOpen WebUI。
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
              , authorization = convert <$> lookup hAuthorization (requestHeaders request)
              , body = eitherDecode content ^? _Right
              }
        )
    "/garbled" -> responseLBS status200 [] "<html>"
    _ -> responseLBS status404 [] "{}"

-- | 偽のOpen WebUIへ繋ぐ送信を渡す。
withServer :: (MonadThrow m, MonadUnliftIO m) => (Transport m -> m a) -> m a
withServer action = withRunInIO \runInIO ->
  testWithApplication (pure application) \port ->
    runInIO (action (httpTransport ("http://127.0.0.1:" <> convert (show port))))

tests :: TopSpec
tests = describe "httpTransport" do
  it "トークンの無い呼び出しにはAuthorizationを付けない" do
    response <-
      withServer \transport ->
        transport Call{method = Get, path = "/echo", authorization = Nothing, body = Nothing}
    response `shouldBe` [aesonQQ|{"method": "GET", "authorization": null, "body": null}|]
  it "トークンのある呼び出しにはBearerで付ける" do
    response <-
      withServer \transport ->
        transport Call{method = Get, path = "/echo", authorization = Just "token", body = Nothing}
    response `shouldBe` [aesonQQ|{"method": "GET", "authorization": "Bearer token", "body": null}|]
  it "本文をJSONとして送る" do
    response <-
      withServer \transport ->
        transport
          Call
            { method = Post
            , path = "/echo"
            , authorization = Just "token"
            , body = Just [aesonQQ|{"ui": {"ctrlEnterToSend": true}}|]
            }
    response
      `shouldBe` [aesonQQ|{
        "method": "POST",
        "authorization": "Bearer token",
        "body": {"ui": {"ctrlEnterToSend": true}}
      }|]
  it "成功ではない状態コードは、パスと状態コードを持つ失敗にする" do
    withServer
      ( \transport ->
          transport Call{method = Get, path = "/missing", authorization = Nothing, body = Nothing}
      )
      `shouldThrow` (== UnexpectedStatus "/missing" 404)
  it "JSONとして読めない本文は、パスを持つ失敗にする" do
    withServer
      ( \transport ->
          transport Call{method = Get, path = "/garbled", authorization = Nothing, body = Nothing}
      )
      `shouldThrow` \case
        UndecodableBody path _ -> path == "/garbled"
        _ -> False
