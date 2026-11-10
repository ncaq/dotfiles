{-# LANGUAGE GHC2024 #-}
{-# LANGUAGE OverloadedStrings #-}

-- | certspotterが検知したイベントを1行のJSONとしてログへ追記するhook。
--
-- certspotterが渡す環境変数の仕様は`man 8 certspotter-script`を参照。
-- `discovered_cert`以外(`malformed_cert`, `error`)も監視自体の異常なので記録する。
--
-- 追記先のログは環境変数`CERTSPOTTER_EVENTS_LOG`で受け取る。
-- `default.nix`のラッパーが設定する。
module Main (main) where

import Data.Aeson (eitherDecodeFileStrict, encode, object, withObject, (.!=), (.:?), (.=))
import Data.Aeson.Types (Pair, parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Exit (die)
import UnliftIO
  ( IOMode (AppendMode)
  , MonadUnliftIO
  , displayException
  , liftIO
  , tryIO
  , withBinaryFile
  )
import UnliftIO.Environment (lookupEnv)

-- | 証明書のJSONから`dns_names`だけを取り出す。
-- 読めなかった時はその理由を`Left`で返す。
-- certspotterはhookが正常終了するとstderrを捨てるので、
-- 理由は呼び出し側でログの行に残して、イベント自体の記録は止めない。
dnsNamesOf :: (MonadUnliftIO m) => FilePath -> m (Either Text [Text])
dnsNamesOf path = do
  -- `eitherDecodeFileStrict`が`Left`にするのはパースの失敗だけで、
  -- ファイルが無いなどの読み取りの失敗はIOExceptionとして投げる。
  result <- tryIO (liftIO (eitherDecodeFileStrict path))
  pure $ case result of
    Left exception -> Left (T.pack (displayException exception))
    Right decoded ->
      either (Left . T.pack) Right $
        decoded >>= parseEither (withObject "cert" (\o -> o .:? "dns_names" .!= []))

main :: IO ()
main = do
  eventsLog <-
    lookupEnv "CERTSPOTTER_EVENTS_LOG"
      >>= maybe (die "certspotter-hook: CERTSPOTTER_EVENTS_LOG is not set") pure
  event <- maybe "unknown" T.pack <$> lookupEnv "EVENT"
  summary <- maybe "" T.pack <$> lookupEnv "SUMMARY"
  issuer <- maybe "" T.pack <$> lookupEnv "ISSUER_DN"
  jsonFile <- lookupEnv "JSON_FILENAME"
  dnsNamesResult <- case jsonFile of
    Just path | event == "discovered_cert" -> dnsNamesOf path
    _ -> pure (Right [])
  now <- round <$> getPOSIXTime :: IO Integer
  -- 読めなかった理由は握り潰さずに`dns_names_error`として同じ行に残す。
  let (dnsNames, dnsNamesError) = case dnsNamesResult of
        Right names -> (names, [])
        Left reason -> ([], ["dns_names_error" .= reason] :: [Pair])
      record =
        object $
          [ "time" .= now
          , "event" .= event
          , "summary" .= summary
          , "dns_names" .= dnsNames
          , "issuer" .= issuer
          ]
            <> dnsNamesError
  withBinaryFile eventsLog AppendMode $ \h -> BL.hPut h (encode record <> "\n")
