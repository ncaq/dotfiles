-- | PRコメントの作成と更新。
--
-- GitHub Actionsの`github-actions[bot]`が書いた、目印で始まるコメントを探して書き換える。
-- 無ければ新しく作る。
-- `gh pr comment`にはコメントを編集する機能が無く、
-- どのみちREST APIを直接叩くので、`gh`を介さずHTTPで話す。
module NvdPrDiff.GitHub
  ( Comment (..)
  , Upsert (..)
  , GitHubFailure (..)
  , botLogin
  , findExisting
  , upsertComment
  ) where

import Data.Text (isPrefixOf)
import Himari
import Network.HTTP.Simple
import NvdPrDiff.Target (Target (..))

-- | PRコメントのうち、探すのに要る部分。
data Comment = Comment
  { commentId :: Integer
  , author :: Text
  , body :: Text
  }
  deriving stock (Eq, Show)

instance FromJSON Comment where
  parseJSON = withObject "comment" \o ->
    Comment
      <$> o .: "id"
      <*> (o .: "user" >>= withObject "user" (.: "login"))
      <*> o .: "body"

-- | 投稿の結果。
data Upsert
  = -- | 既にあったコメントを書き換えた。そのID。
    Updated Integer
  | Created
  deriving stock (Eq, Show)

-- | GitHubと話せなかった理由。
data GitHubFailure
  = -- | 成功でない応答。状態コードと本文。
    RequestFailed Int Text
  | -- | 応答のJSONを読めなかった。aesonの説明。
    ResponseUnreadable Text
  deriving stock (Eq, Show)

instance Exception GitHubFailure where
  displayException = \case
    RequestFailed status detail ->
      "GitHubの応答が" <> show status <> "でした: " <> convert detail
    ResponseUnreadable detail -> "GitHubの応答を読めませんでした: " <> convert detail

-- | GitHub Actionsの既定のトークンで投稿した時の作者。
botLogin :: Text
botLogin = "github-actions[bot]"

-- | 指定の作者が書いた、目印で始まる最初のコメントのID。
findExisting :: Text -> Text -> [Comment] -> Maybe Integer
findExisting author marker =
  fmap (.commentId) . find \comment -> comment.author == author && marker `isPrefixOf` comment.body

-- | 目印で始まる自分のコメントがあれば書き換え、無ければ作る。
upsertComment :: (MonadIO m, MonadLogger m, MonadThrow m) => Target -> Text -> Text -> m Upsert
upsertComment target marker body = do
  comments <- listComments target
  case findExisting botLogin marker comments of
    Just existing -> do
      _ <-
        request
          target
          "PATCH"
          ("repos/" <> target.repository <> "/issues/comments/" <> convert (show existing))
          (Just body)
      logInfoN ("コメントを更新しました: " <> convert (show existing))
      pure (Updated existing)
    Nothing -> do
      _ <- request target "POST" (commentsPath target) (Just body)
      logInfoN "コメントを作成しました"
      pure Created

commentsPath :: Target -> Text
commentsPath target =
  "repos/" <> target.repository <> "/issues/" <> convert (show target.prNumber) <> "/comments"

-- | 1ページに収める数。GitHubの上限。
perPage :: Int
perPage = 100

-- | PRの全てのコメント。1ページに満たなくなるまでめくる。
listComments :: (MonadIO m, MonadLogger m, MonadThrow m) => Target -> m [Comment]
listComments target = page 1
 where
  page n = do
    raw <-
      request
        target
        "GET"
        ( commentsPath target
            <> "?per_page="
            <> convert (show perPage)
            <> "&page="
            <> convert (show (n :: Int))
        )
        Nothing
    comments <- either (throwM . ResponseUnreadable . convert) pure (eitherDecode raw)
    if length comments < perPage then pure comments else (comments <>) <$> page (n + 1)

-- | REST APIを1回呼んで本文を返す。本文を渡せば`body`だけのJSONとして送る。
request
  :: (MonadIO m, MonadLogger m, MonadThrow m)
  => Target -> ByteString -> Text -> Maybe Text -> m LazyByteString
request target method path payload = do
  logDebugN (convert method <> " " <> path)
  base <- parseRequest (convert ("https://api.github.com/" <> path))
  let prepared =
        base
          & setRequestMethod method
          & setRequestHeader "Authorization" ["Bearer " <> convert target.token]
          & setRequestHeader "Accept" ["application/vnd.github+json"]
          & setRequestHeader "X-GitHub-Api-Version" ["2022-11-28"]
          & setRequestHeader "User-Agent" ["nvd-pr-diff"]
          & maybe id (setRequestBodyJSON . bodyOnly) payload
  response <- httpLBS prepared
  let status = getResponseStatusCode response
  if status `div` 100 == 2
    then pure (getResponseBody response)
    else throwM (RequestFailed status (convert (getResponseBody response)))
 where
  bodyOnly :: Text -> Map Text Text
  bodyOnly body = mempty & at "body" ?~ body
