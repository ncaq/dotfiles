-- | イベントのログの読み書き。
--
-- 1行に1つのJSONを並べたファイルである。
module CertspotterMackerel.EventLog
  ( appendEvent
  , readEvents
  , parseEvents
  ) where

import CertspotterMackerel.Event (Event)
import CertspotterMackerel.EventLogPath (EventLogPath (..))
import Data.ByteString qualified as B
import Himari

-- | イベントをログの末尾へ1行として足す。
appendEvent :: (MonadUnliftIO m) => EventLogPath -> Event -> m ()
appendEvent (EventLogPath path) event =
  withBinaryFile path AppendMode \handle' ->
    liftIO (B.hPut handle' (convert (encode event) <> "\n"))

-- | ログのイベントを全て読む。
--
-- hookがまだ一度も呼ばれていなければログは無いので、その時は`Nothing`を返す。
readEvents :: (MonadIO m) => EventLogPath -> m (Maybe [Event])
readEvents (EventLogPath path) = do
  exists <- doesFileExist path
  if exists
    then Just . parseEvents <$> liftIO (B.readFile path)
    else pure Nothing

-- | ログの中身からイベントを取り出す。
--
-- 壊れた行は黙って飛ばす。
-- 1行壊れているだけで監視全体が止まるよりは、残りの行を見られるほうが良い。
parseEvents :: ByteString -> [Event]
parseEvents = rights . fmap eitherDecodeStrict . B.split newline
 where
  newline = 10
