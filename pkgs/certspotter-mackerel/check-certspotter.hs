{-# LANGUAGE GHC2024 #-}
{-# LANGUAGE OverloadedStrings #-}

-- | `certspotter-hook`が書いたログを読むMackerelのチェック。
--
-- 一定期間以内のイベントがあればCRITICALにする。
-- アラートが一定期間開いたままになることで見落としを防ぐ。
--
-- 設定は環境変数で受け取る。`default.nix`のラッパーが設定する。
--
-- [@CERTSPOTTER_EVENTS_LOG@] `certspotter-hook`が追記するログ。
-- [@CERTSPOTTER_ALERT_WINDOW_SECONDS@] この秒数以内のイベントがあればCRITICALにする。
-- [@CERTSPOTTER_SERVICE_UNIT@] 動いていることを確かめるsystemdのユニット。
--   空か未設定ならば確認を省く。ビルドサンドボックス内のテストで使うため。
module Main (main) where

import Control.Monad (unless)
import Data.Aeson (FromJSON (parseJSON), eitherDecodeStrict, withObject, (.!=), (.:), (.:?))
import Data.ByteString.Char8 qualified as B8
import Data.Char
  ( GeneralCategory (Control, Format, LineSeparator, ParagraphSeparator)
  , generalCategory
  )
import Data.Either (rights)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Time.Clock.POSIX (getPOSIXTime, posixSecondsToUTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import System.Exit (ExitCode (ExitFailure, ExitSuccess), exitWith)
import System.IO (hSetEncoding, utf8)
import Text.Read (readMaybe)
import UnliftIO (MonadIO, liftIO, stdout)
import UnliftIO.Directory (doesFileExist)
import UnliftIO.Environment (lookupEnv)
import UnliftIO.Process (readProcessWithExitCode)

data Event = Event
  { time :: Integer
  , event :: Text
  , summary :: Text
  , dnsNames :: [Text]
  , issuer :: Text
  , -- hookが証明書のJSONを読めなかった時の理由。
    dnsNamesError :: Maybe Text
  }

instance FromJSON Event where
  parseJSON = withObject "Event" $ \o ->
    Event
      <$> o .: "time"
      <*> o .:? "event" .!= ""
      <*> o .:? "summary" .!= ""
      <*> o .:? "dns_names" .!= []
      <*> o .:? "issuer" .!= ""
      <*> o .:? "dns_names_error"

-- | 外部由来の文字列から行や見え方を崩す文字を除いて、Mackerelへ渡す1行に収める。
-- Cc(制御文字)だけでなく、
-- Cf(U+202Eのような双方向制御やゼロ幅文字)とU+2028/U+2029(行区切りと段落区切り)も、
-- 通知上でドメイン名や発行者の見え方を偽装できるので空白にする。
sanitize :: Text -> Text
sanitize = T.map (\c -> if isUnsafe c then ' ' else c)
 where
  isUnsafe c = case generalCategory c of
    Control -> True
    Format -> True
    LineSeparator -> True
    ParagraphSeparator -> True
    _ -> False

-- | `event`はcertspotterが決める値だが、ログが壊れていた時のために同じ方針で扱う。
render :: Event -> Text
render e =
  T.unwords $
    [ timestamp
    , sanitize (event e) <> ":"
    , sanitize (summary e)
    , "(" <> sanitize (T.intercalate "," (dnsNames e)) <> ")"
    , "issuer=" <> sanitize (issuer e)
    ]
      <> foldMap (\reason -> ["dns_names_error=" <> sanitize reason]) (dnsNamesError e)
 where
  timestamp =
    T.pack (formatTime defaultTimeLocale "%FT%TZ" (posixSecondsToUTCTime (fromInteger (time e))))

-- | Mackerelの規約どおり、メッセージを出してから状態に対応する終了コードで終わる。
-- 戻ってこないので任意の`m a`として呼べる。
exitWithMessages :: (MonadIO m) => Int -> [Text] -> m a
exitWithMessages code messages = liftIO $ do
  mapM_ T.putStrLn messages
  exitWith (ExitFailure code)

-- | CRITICALはexit 2。
critical :: (MonadIO m) => [Text] -> m a
critical = exitWithMessages 2

-- | UNKNOWNはexit 3。
-- 設定が読めない時は監視そのものができていないので、OKにもCRITICALにもしない。
unknown :: (MonadIO m) => [Text] -> m a
unknown = exitWithMessages 3

-- | 必須の環境変数を読む。無ければUNKNOWNで終わる。
requireEnv :: (MonadIO m) => String -> m String
requireEnv name =
  lookupEnv name
    >>= maybe (unknown ["certspotter UNKNOWN: " <> T.pack name <> " is not set"]) pure

main :: IO ()
main = do
  hSetEncoding stdout utf8
  eventsLog <- requireEnv "CERTSPOTTER_EVENTS_LOG"
  alertWindowSecondsText <- requireEnv "CERTSPOTTER_ALERT_WINDOW_SECONDS"
  alertWindowSeconds <-
    maybe
      (unknown ["certspotter UNKNOWN: CERTSPOTTER_ALERT_WINDOW_SECONDS is not an integer"])
      pure
      (readMaybe alertWindowSecondsText :: Maybe Integer)
  serviceUnit <- lookupEnv "CERTSPOTTER_SERVICE_UNIT"
  case serviceUnit of
    Just unit | not (null unit) -> do
      (code, _, _) <- readProcessWithExitCode "systemctl" ["is-active", "--quiet", unit] ""
      unless (code == ExitSuccess) $ critical ["certspotter CRITICAL: service not running"]
    _ -> pure ()
  exists <- doesFileExist eventsLog
  if not exists
    then T.putStrLn "certspotter OK (no events yet)"
    else do
      now <- round <$> getPOSIXTime
      contents <- B8.readFile eventsLog
      -- 壊れた行は黙って飛ばす。
      -- 1行壊れているだけで監視全体が止まるよりは、残りの行を見られるほうが良い。
      let events = rights (eitherDecodeStrict <$> B8.lines contents)
          recent = filter (\e -> time e >= now - alertWindowSeconds) events
      if null recent
        then T.putStrLn "certspotter OK"
        else
          critical
            ("certspotter CRITICAL: new certificate transparency events" : fmap render recent)
