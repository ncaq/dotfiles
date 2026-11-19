-- | 標準入力から受け取るstoreパスの一覧。
module NixCachePushNcaq.Niks3.StorePaths
  ( storePathsFrom
  ) where

import Data.Text (lines)
import Himari hiding (lines)

-- | 1行に1つずつ書かれたstoreパスを読む。空の行は捨てる。
--
-- 結果はそのまま`niks3`の引数にするので`String`で返す。
storePathsFrom :: Text -> [String]
storePathsFrom = fmap convert . filter (/= mempty) . lines
