-- | certspotterが書き出す証明書のJSON。
--
-- 使うのはSANの一覧だけなので、それだけを読む。
module CertspotterMackerel.Certificate
  ( Certificate (..)
  , readCertificate
  ) where

import CertspotterMackerel.DnsName (DnsName)
import Himari

newtype Certificate = Certificate
  { dnsNames :: [DnsName]
  }
  deriving stock (Eq, Show)

-- | `dns_names`が無い証明書は、SANが無いものとして読む。
instance FromJSON Certificate where
  parseJSON = withObject "Certificate" \o -> Certificate <$> o .:? "dns_names" .!= []

-- | 証明書のJSONファイルを読む。
--
-- 読めなかった時はその理由を`Left`で返す。
-- certspotterはhookが正常終了すると標準エラー出力を捨てるので、
-- 理由は呼び出し側でログの行に残して、イベント自体の記録は止めない。
readCertificate :: (MonadUnliftIO m) => FilePath -> m (Either Text Certificate)
readCertificate path =
  -- `eitherDecodeFileStrict`が`Left`にするのはパースの失敗だけで、
  -- ファイルが無いなどの読み取りの失敗は`IOException`として投げる。
  either (Left . convert . displayException) (over _Left convert)
    <$> tryIO (liftIO (eitherDecodeFileStrict path))
