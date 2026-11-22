-- | 探す対象にするゴミ箱の名前と、探さない場所。
module TrashEmptyStray.TrashDirName
  ( isTrashDirName
  , isHomeTrashPath
  ) where

import Data.Char (isDigit)
import Data.List (isSuffixOf, stripPrefix)
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

-- | ホームのゴミ箱(`.local/share/Trash`)を指すパスかどうか。
--
-- この中には捨てたディレクトリがそのまま入っていて、その中に`.Trash-<uid>`があることもある。
-- それを掃除すると捨てたものの中身を書き換えてしまうので、探索はこの中へ降りない。
-- 中身の期限は`trash-empty --all-users`が外側のエントリの単位で見ている。
isHomeTrashPath :: FilePath -> Bool
isHomeTrashPath = isSuffixOf "/.local/share/Trash"
