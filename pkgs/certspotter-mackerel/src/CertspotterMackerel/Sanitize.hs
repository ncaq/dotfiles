-- | 外部由来の文字列を、通知へ出しても行や見え方を崩さない形にする。
module CertspotterMackerel.Sanitize
  ( sanitize
  ) where

import Data.Char (GeneralCategory (..), generalCategory)
import Himari

-- | 行や見え方を崩す文字を空白にして、Mackerelへ渡す1行に収める。
--
-- Cc(制御文字)だけでなく、
-- Cf(U+202Eのような双方向制御やゼロ幅文字)とU+2028/U+2029(行区切りと段落区切り)も、
-- 通知上でドメイン名や発行者の見え方を偽装できるので空白にする。
sanitize :: Text -> Text
sanitize = over each \character -> if unsafe character then ' ' else character
 where
  unsafe character = case generalCategory character of
    Control -> True
    Format -> True
    LineSeparator -> True
    ParagraphSeparator -> True
    _ -> False
