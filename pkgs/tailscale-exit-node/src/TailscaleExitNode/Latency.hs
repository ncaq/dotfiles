-- | `tailscale ping`の出力からレイテンシを読む。
module TailscaleExitNode.Latency
  ( parsePingLatency
  ) where

import Data.Text qualified as T
import Himari hiding (try)
import Text.Megaparsec hiding (many, some)
import Text.Megaparsec.Char
import Text.Megaparsec.Char.Lexer (scientific)

type Parser = Parsec Void Text

-- | 出力の中の最後のpongの行からレイテンシを読む。
--
-- pongの行は以下の形をしている。
--
-- > pong from seminar (fd7a:115c:a1e0::b934:6c4a) via [2001:db8::1]:41641 in 4ms
--
-- 出力にはpong以外の行も混ざる。
-- 直接の経路ができるまで待つのが既定の動作なので、
-- DERP経由のpongだけが返ると、その後に`direct connection not established`が出る。
-- 行ごとに読んで、pongとして読めた行だけを見る。
--
-- pingが届かなかった時などpongの行が無い出力は`Nothing`にする。
parsePingLatency :: Text -> Maybe NominalDiffTime
parsePingLatency = lastMay . mapMaybe (parseMaybe pong) . T.lines

-- | pongの1行。行の末尾のレイテンシを返す。
--
-- ノード名や経路の表記には踏み込まず、行の末尾が` in `とレイテンシで終わることだけを見る。
-- 途中に` in `が現れても、その後ろがレイテンシで行が終わっていなければ読み進める。
pong :: Parser NominalDiffTime
pong = string "pong from " *> skipManyTill anySingle (try (string " in " *> duration <* eof))

-- | Goの`time.Duration`の表記のうち、`tailscale ping`が出す形を読む。
--
-- レイテンシはミリ秒へ丸められている。
-- 1秒未満は`4ms`、ちょうど0は`0s`、1秒以上は`1.234s`のように出る。
-- 分より上の単位が付くほど遅い時は読まない。読めなくても外部とみなす結果は変わらない。
duration :: Parser NominalDiffTime
duration = (*) . realToFrac <$> scientific <*> unit
 where
  unit = (0.001 <$ string "ms") <|> (1 <$ string "s")
