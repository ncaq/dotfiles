-- | 公式CLIとComfyUIのHTTP APIを呼ぶ。
--
-- 公式の`comfy`には`--json`を付けて封筒の形で受け取る。
-- 終了コードが0でなくても封筒は出るので、
-- 封筒の`error`を読んで理由を見せる。
--
-- 投入と履歴の取得だけは直接HTTPを叩く。
-- 公式の`comfy run`は投げる前に自前の検証を通し、
-- `Lora Loader (LoraManager)`の`text`のような拡張だけが知る型を
-- 「リンクに値が書かれている」として弾く。
-- サーバ自身は受け付けるので、
-- 検証を飛ばして投げるにはこちらから`POST /prompt`するしかない。
module ComfyWorkflow.Comfy
  ( Target (..)
  , parseAuthority
  , authorityOf
  , ComfyFailure (..)
  , comfyJson
  , postPrompt
  , getHistory
  ) where

import ComfyWorkflow.Prompt (Prompt)
import ComfyWorkflow.Slot (Envelope (..), describeError)
import Himari
import Network.HTTP.Simple

data Target = Target
  { host :: Text
  , port :: Int
  }
  deriving stock (Eq, Show)

-- | `host:port`を分ける。
--
-- 公式CLIは`--host`と`--port`を別々に受け取るので、
-- 環境変数の`host:port`をここで分ける。
parseAuthority :: Text -> Either Text Target
parseAuthority authority = case break (== ':') (reverse (convert authority)) of
  (reversedPort, ':' : reversedHost)
    | not (null reversedHost)
    , Just port <- readMay (reverse reversedPort) ->
        Right Target{host = convert (reverse reversedHost), port}
  _ -> Left ("接続先は`host:port`の形で指定してください: " <> authority)

newtype ComfyFailure = ComfyFailure Text
  deriving stock (Show)

instance Exception ComfyFailure

-- | `Target`を接続先の`host:port`の形に戻す。`parseAuthority`の逆。
authorityOf :: Target -> Text
authorityOf target = target.host <> ":" <> convert (show target.port)

-- | `comfy --json <args>`を走らせて、封筒の中身を返す。
--
-- 標準エラー出力は繋いだままにする。
-- 変換の警告などはそちらに出るので、見えた方が良い。
comfyJson :: (FromJSON a, MonadIO m, MonadLogger m, MonadThrow m) => [Text] -> m a
comfyJson args = do
  logDebugN command
  (_, out) <- readProcessStdout (proc "comfy" (fmap convert ("--json" : args)))
  envelope <- either (throwM . ComfyFailure . malformed out . convert) pure (eitherDecode out)
  case envelope of
    Envelope{ok = True, payload = Just value} -> pure value
    Envelope{failure = Just err} ->
      throwM (ComfyFailure (command <> " が失敗しました: " <> describeError err))
    Envelope{} -> throwM (ComfyFailure (command <> " の応答に中身がありません"))
 where
  command = "comfy " <> convert (unwords (fmap convert args))
  malformed out reason = command <> " の応答を読めませんでした: " <> reason <> "\n" <> convert out

-- | API形式のプロンプトを`POST /prompt`へ投げて`prompt_id`を返す。
--
-- 検証で弾かれた場合は本文にどのノードの何が悪いのかが入っているので、
-- 本文ごと見せる。
--
-- ソケットアクティベーションで寝ているComfyUIを起こすのは、
-- これより前に走る`comfy workflow slots`なので、
-- ここでは既定の応答待ちの長さで足りる。
postPrompt :: (MonadIO m, MonadLogger m, MonadThrow m) => Target -> Prompt -> m Text
postPrompt target prompt = do
  let url = "http://" <> authorityOf target <> "/prompt"
      body :: Map Text Value
      body = mempty & at "prompt" ?~ toJSON prompt
  logDebugN ("POST " <> url)
  request <- parseRequest (convert url)
  response <- httpLBS (setRequestMethod "POST" (setRequestBodyJSON body request))
  out <- bodyOrThrow "ComfyUIが受け付けませんでした" response
  PromptResponse promptId <-
    either (throwM . ComfyFailure . ("投入の応答を読めませんでした: " <>) . convert) pure (eitherDecode out)
  pure promptId

newtype PromptResponse = PromptResponse Text

instance FromJSON PromptResponse where
  parseJSON = withObject "投入の応答" \o -> PromptResponse <$> o .: "prompt_id"

-- | `/history/<prompt_id>`を読む。
getHistory :: (MonadIO m, MonadLogger m, MonadThrow m) => Target -> Text -> m Value
getHistory target promptId = do
  let url = "http://" <> authorityOf target <> "/history/" <> promptId
  logDebugN ("GET " <> url)
  request <- parseRequest (convert url)
  response <- httpLBS request
  out <- bodyOrThrow "履歴を取得できませんでした" response
  either (throwM . ComfyFailure . ("履歴を読めませんでした: " <>) . convert) pure (eitherDecode out)

-- | 応答の本文を返す。成功の状態でなければ本文を添えて例外にする。
bodyOrThrow :: (MonadThrow m) => Text -> Response LazyByteString -> m LazyByteString
bodyOrThrow failurePrefix response
  | getResponseStatusCode response `div` 100 == 2 = pure (getResponseBody response)
  | otherwise = throwM (ComfyFailure (failurePrefix <> ": " <> convert (getResponseBody response)))
