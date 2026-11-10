-- | Open WebUIへの送信。
--
-- 送信を関数として受け渡すのは、テストで実際のOpen WebUIへ繋がずに済ませるためである。
module UserSettingsSync.Transport
  ( Transport
  , httpTransport
  ) where

import Himari
import Network.HTTP.Simple
import UserSettingsSync.Call (Call (..), Method (..))
import UserSettingsSync.Failure (ApiFailure (..))
import UserSettingsSync.Token (Token (..))

-- | 呼び出しを送って、応答の本文のJSONを返す。
--
-- 成功ではない状態コードは`ApiFailure`として投げる。
type Transport m = Call -> m Value

-- | HTTPで送る。
--
-- 応答待ちの上限はhttp-clientの既定の30秒に任せる。
httpTransport :: (MonadIO m, MonadThrow m) => Text -> Transport m
httpTransport url call = do
  base <- parseRequest (convert (url <> call.path))
  response <- httpLBS (withBody (authorized (setRequestMethod verb base)))
  let status = getResponseStatusCode response
      content = getResponseBody response
  unless (status `div` 100 == 2) (throwM (UnexpectedStatus call.path status))
  either (throwM . UndecodableBody call.path . convert) pure (eitherDecode content)
 where
  verb = case call.method of
    Get -> "GET"
    Post -> "POST"
  authorized = case call.authorization of
    Just (Token token) -> setRequestBearerAuth (convert token)
    Nothing -> id
  withBody = maybe id setRequestBodyJSON call.body
