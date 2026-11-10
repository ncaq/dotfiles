-- | `tailscale ping`の出力からレイテンシを読む。
module TailscaleExitNode.Latency
  ( parsePingLatency
  ) where

import Data.Char (isDigit)
import Data.Text qualified as T
import Himari

-- | pongの行の末尾にあるレイテンシを読む。
--
-- 出力は以下の形をしている。
--
-- > pong from seminar (100.82.4.93) via 192.168.10.88:41641 in 4ms
--
-- レイテンシはGoの`time.Duration`の表記で、ミリ秒へ丸められている。
-- 1秒未満は`4ms`、ちょうど0は`0s`、1秒以上は`1.234s`のように出る。
--
-- pingが届かなかった時などレイテンシが無い出力は`Nothing`にする。
parsePingLatency :: Text -> Maybe NominalDiffTime
parsePingLatency output = do
  -- 最後の` in `の後ろを見る。ノード名に` in `が入っていても取り違えない。
  let (before, duration) = T.breakOnEnd " in " (T.strip output)
  guard (not (T.null before))
  let (number, unit) = T.span (\character -> isDigit character || character == '.') duration
  scale <- case unit of
    "ms" -> Just 0.001
    "s" -> Just 1
    _ -> Nothing
  -- 先頭が数字でないものは読まない。`readMay`は`.5`を読まないが、念のため明示する。
  guard (maybe False (isDigit . fst) (T.uncons number))
  value :: Pico <- readMay (convert number)
  pure (realToFrac value * scale)
