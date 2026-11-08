-- | 取り出しと書き戻しの2つのコマンド。
--
-- `extract`で取り出したテンプレートへ`patch`コマンドで差分を当て、
-- `embed`で同じGGUFへ書き戻すことを想定している。
-- 差分の適用自体はこのプログラムの仕事ではない。
--
-- どちらも位置を返すので、呼び出し側は何を触ったかを報告できる。
module PatchGgufChatTemplate.Command
  ( extract
  , embed
  ) where

import Data.ByteString qualified as B
import Himari
import PatchGgufChatTemplate.Gguf.Locate (Span (..), locateChatTemplate)
import PatchGgufChatTemplate.Gguf.Reader (readExact)
import PatchGgufChatTemplate.Pad (padToLength)

-- | GGUFからチャットテンプレートを取り出してファイルへ書く。
extract :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => FilePath -> FilePath -> m Span
extract ggufPath templatePath = do
  (location, template) <- withBinaryFile ggufPath ReadMode \file -> do
    location <- locateChatTemplate file
    -- `locateChatTemplate`はハンドルを値の先頭で止めるので、そのまま読める。
    template <- readExact file location.size
    pure (location, template)
  writeBinaryFile templatePath template
  logInfoN ("tokenizer.chat_templateを取り出しました: " <> describe location)
  pure location

-- | ファイルのチャットテンプレートをGGUFへ書き戻す。
--
-- 長さを揃えられないことは書き込む前に分かるので、その時はGGUFに触れない。
embed :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => FilePath -> FilePath -> m Span
embed ggufPath templatePath = do
  template <- liftIO (B.readFile templatePath)
  location <- withBinaryFile ggufPath ReadWriteMode \file -> do
    location <- locateChatTemplate file
    padded <- either throwM pure (padToLength template location.size)
    -- `locateChatTemplate`はハンドルを値の先頭で止めるので、そのまま書ける。
    liftIO (B.hPut file padded)
    pure location
  logInfoN ("tokenizer.chat_templateを書き戻しました: " <> describe location)
  pure location

describe :: Span -> Text
describe location =
  "オフセット" <> convert (show location.offset) <> ", " <> convert (show location.size) <> "バイト"
