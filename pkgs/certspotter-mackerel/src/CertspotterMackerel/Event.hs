-- | ログの1行になるイベント。
--
-- hookが書いてチェックが読む。
-- 書く側と読む側が同じ型を通るので、鍵の名前がずれることは無い。
--
-- JSONにするのは、`summary`や`issuer`やSANがCAとCTログ由来の信頼できない値だからである。
-- 区切り文字で並べると改行やタブで列がずれたり偽の行を作られたりするが、
-- aesonに任せれば必ず1行のJSONになる。
module CertspotterMackerel.Event
  ( Event (..)
  ) where

import CertspotterMackerel.DnsName (DnsName)
import CertspotterMackerel.EventKind (EventKind)
import CertspotterMackerel.Issuer (Issuer)
import CertspotterMackerel.Summary (Summary)
import Himari

data Event = Event
  { time :: UTCTime
  -- ^ hookが呼ばれた時刻。
  , event :: EventKind
  , summary :: Summary
  , dnsNames :: [DnsName]
  , issuer :: Issuer
  , dnsNamesError :: Maybe Text
  -- ^ hookが証明書のJSONを読めなかった時の理由。
  }
  deriving stock (Eq, Generic, Show)
  deriving
    (ToJSON)
    via CustomJSON '[FieldLabelModifier CamelToSnake, OmitNothingFields] Event

-- | 時刻以外は無くても読む。
--
-- 鍵が足りない行を捨てるより、分かる範囲で通知に出した方が見落としが無い。
-- 時刻だけは、アラート期間に入るかどうかを決められないので必須にする。
--
-- 時刻はaesonの`UTCTime`の形、つまりISO 8601の文字列で書く。
-- 前の版はUNIX時刻の秒を数値で書いていたので、その形の行も読む。
-- 読めないと、版を上げた時点でアラート期間の中にあったイベントが通知から消えてしまう。
instance FromJSON Event where
  parseJSON = withObject "Event" \o ->
    Event
      <$> (o .: "time" <|> posixSecondsToUTCTime <$> o .: "time")
      <*> o .:? "event" .!= ""
      <*> o .:? "summary" .!= ""
      <*> o .:? "dns_names" .!= []
      <*> o .:? "issuer" .!= ""
      <*> o .:? "dns_names_error"
