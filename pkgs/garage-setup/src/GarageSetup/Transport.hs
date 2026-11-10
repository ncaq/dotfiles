-- | Admin APIへの送信。
--
-- 送信を関数として受け渡すのは、テストで実際のGarageへ繋がずに済ませるためである。
module GarageSetup.Transport
  ( Transport
  , httpTransport
  ) where

import GarageSetup.AdminToken (AdminToken (..))
import GarageSetup.Call (Call (..), Method (..))
import GarageSetup.Failure (ApiFailure (..))
import Himari
import Network.HTTP.Simple

-- | 呼び出しを送って、応答の本文のJSONを返す。
--
-- 成功ではない状態コードは`ApiFailure`として投げる。
type Transport m = Call -> m Value

-- | HTTPで送る。
--
-- 応答待ちの上限はhttp-clientの既定の30秒に任せる。
httpTransport :: (MonadIO m, MonadThrow m) => Text -> AdminToken -> Transport m
httpTransport api (AdminToken token) call = do
  base <- parseRequest (convert (api <> call.path))
  response <- httpLBS (withBody (addressed base))
  let status = getResponseStatusCode response
      content = getResponseBody response
  unless (status `div` 100 == 2) (throwM (UnexpectedStatus call.path status))
  -- 本文の無い成功は、中身の無い値として扱う。
  if content == mempty
    then pure Null
    else either (throwM . UndecodableBody call.path . convert) pure (eitherDecode content)
 where
  addressed =
    setRequestMethod (verb call.method)
      . setRequestQueryString [(convert key, Just (convert value)) | (key, value) <- call.query]
      . setRequestBearerAuth (convert token)
  withBody = maybe id setRequestBodyJSON call.body
  verb = \case
    Get -> "GET"
    Post -> "POST"
