-- | 秒数で書かれた時間の長さの読み方。
module CertspotterMackerel.Seconds
  ( parseSeconds
  ) where

import Himari

-- | 0以上の整数の秒数を、時間の長さとして読む。
--
-- 負の長さは意味を持たないので読まない。
parseSeconds :: Text -> Maybe NominalDiffTime
parseSeconds raw = fromInteger <$> mfilter (0 <=) (readMay (convert raw))
