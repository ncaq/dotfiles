-- | テンプレートを元のバイト長へ揃える。
--
-- GGUFのメタデータ文字列は長さプレフィックス付きで並んでいる。
-- 長さを変えるとそれ以降の全てのオフセットがずれてファイル全体の書き直しになるため、
-- 書き戻す時は元と同じバイト長に保つ。
--
-- 縮んだ分は末尾へJinjaのコメントを足して埋める。
-- コメントは描画結果に何も足さないので、埋めた分がプロンプトに現れることはない。
--
-- 伸びた場合は埋めようがないので拒否する。
-- その場合は差分の側を短く書き直す必要がある。
module PatchGgufChatTemplate.Pad
  ( PadFailure (..)
  , padToLength
  ) where

import Data.ByteString qualified as B
import Himari

-- | 元のバイト長へ揃えられない理由。
data PadFailure
  = -- | 元より長い。超えたバイト数。
    TemplateTooLong Int
  | -- | 空のコメントすら入らない端数。余ったバイト数。
    PaddingTooSmall Int
  deriving stock (Eq, Show)

instance Exception PadFailure where
  displayException = \case
    TemplateTooLong excess -> "差分を当てたテンプレートが元より" <> show excess <> "バイト長いです"
    PaddingTooSmall padding -> show padding <> "バイトの余りはJinjaのコメントで埋められません"

-- | Jinjaのコメントは`{#`と`#}`で4バイト使う。
-- これ未満の端数は埋めようがない。
commentOverhead :: Int
commentOverhead = 4

-- | 末尾へJinjaのコメントを足して指定のバイト長へ揃える。
padToLength :: ByteString -> Int -> Either PadFailure ByteString
padToLength template size
  | padding < 0 = Left (TemplateTooLong (negate padding))
  | padding == 0 = Right template
  | padding < commentOverhead = Left (PaddingTooSmall padding)
  | otherwise = Right (template <> "{#" <> B.replicate (padding - commentOverhead) space <> "#}")
 where
  padding = size - B.length template
  space = 0x20
