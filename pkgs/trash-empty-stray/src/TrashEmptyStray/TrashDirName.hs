-- | 探す対象にするゴミ箱の名前。
module TrashEmptyStray.TrashDirName
  ( isTrashDirName
  ) where

import Data.Char (isDigit)
import Data.List (stripPrefix)
import Himari

-- | `.Trash-<uid>`の形の名前かどうか。
--
-- `trash-put`がホーム以外のボリュームに作るゴミ箱の名前である。
-- `~/.local/share/Trash`は`trash-empty --all-users`が見ているので対象にしない。
-- 管理者が用意する`.Trash/<uid>`の形も、うっかり作られるものではないので対象にしない。
isTrashDirName :: FilePath -> Bool
isTrashDirName name = case stripPrefix ".Trash-" name of
  Just uid -> not (null uid) && all isDigit uid
  Nothing -> False
