-- | 標準入力から受け取るstoreパスの一覧。
module NixCachePushNcaq.Niks3.StorePaths
  ( storePathsFrom
  ) where

import Himari

-- | 1行に1つずつ書かれたstoreパスを読む。空の行は捨てる。
storePathsFrom :: String -> [String]
storePathsFrom = filter (/= mempty) . lines
