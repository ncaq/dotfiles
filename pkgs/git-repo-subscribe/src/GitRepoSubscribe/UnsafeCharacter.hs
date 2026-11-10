-- | Gitの引数1つとして渡す値に含めてはいけない文字の判定。
module GitRepoSubscribe.UnsafeCharacter
  ( hasUnsafeCharacter
  ) where

import Data.Char (isControl, isSpace)
import Himari

-- | 空白か制御文字を含むか。
--
-- 含む値は、ログや設定に写した時に複数の値や別の行に見えてしまう。
hasUnsafeCharacter :: Text -> Bool
hasUnsafeCharacter value = any (\c -> isSpace c || isControl c) (convert value :: String)
