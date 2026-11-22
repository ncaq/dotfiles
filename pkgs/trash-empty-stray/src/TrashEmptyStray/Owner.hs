-- | ディレクトリの所有者の権限でのコマンドの実行。
module TrashEmptyStray.Owner
  ( runAsOwnerInside
  ) where

import Himari
import System.Posix.Files (fileOwner, getFdStatus)
import System.Posix.IO
  ( OpenFileFlags (..)
  , OpenMode (ReadOnly)
  , closeFd
  , defaultFileFlags
  , openFd
  )
import System.Posix.Types (GroupID, UserID)
import System.Posix.User (getEffectiveUserID, getUserEntryForID, userGroupID)
import TrashEmptyStray.Failure (OwnerFailure (..))
import TrashEmptyStray.FoundTrashDir (DirIdentity, identityOf)

-- | ディレクトリの中を作業ディレクトリにして、その所有者の権限でコマンドを実行する。
--
-- 探して見つけたゴミ箱は、誰でも好きな場所に好きな中身で作れる。
-- `trash-empty`は`files`がシンボリックリンクでも辿って中身を消すので、
-- rootのまま掃除すると、リンクを仕込んだ者に任意の場所を消させられてしまう。
-- 所有者の権限へ落としておけば、消せるのは所有者が自分で消せるものだけになる。
--
-- ゴミ箱の名前のuidではなく所有者を使う。
-- 名前は作った者が自由に決められるので、権限の根拠にできない。
-- rootが作ったゴミ箱はrootの権限のまま掃除する。
-- root所有のディレクトリは他の者には作れず、中も書き換えられない。
--
-- 手順は以下の通りである。
--
-- - シンボリックリンクを辿らずにディレクトリを開いて、開いたものの所有者を見る
-- - 開いたディレクトリを作業ディレクトリにしてコマンドを起動する
-- - 所有者が今の実効ユーザと違えば、`setpriv`を挟んで権限を落とす
--
-- 作業ディレクトリは見つけた時のパスではなく、`/proc/self/fd`の下の開いたディレクトリで指す。
-- 所有者を見た後に親のディレクトリを差し替えられても、見た実体を掴んだままにするためである。
--
-- 権限を落とすのを`setpriv`に任せるのは、スレッドを持つこのプロセスの中でuidを変えないためである。
-- グループは所有者の主グループにして、補助グループは`setpriv`が空にする。
--
-- 開いたものが、探索で見つけた時と同じ実体かも確かめる。
-- シンボリックリンクを辿らないのはパスの最後の要素だけなので、
-- 見つけてから開くまでの間に途中のディレクトリをリンクへ差し替えられると、
-- 探索が除いた場所にあるゴミ箱を開いてしまう。
-- 違う実体だった時は`ReplacedSinceFound`を投げて、何も実行しない。
--
-- コマンドが成功で終わらなかった時は`ChildFailed`を投げる。
runAsOwnerInside
  :: (MonadThrow m, MonadUnliftIO m) => DirIdentity -> FilePath -> FilePath -> [String] -> m ()
runAsOwnerInside expected path command arguments =
  bracket (liftIO (openFd path ReadOnly flags)) (liftIO . closeFd) \fd -> do
    status <- liftIO (getFdStatus fd)
    unless (identityOf status == expected) (throwM ReplacedSinceFound)
    effective <- liftIO getEffectiveUserID
    let owner = fileOwner status
    group <- primaryGroupOf owner
    let
      process
        | effective == owner = proc command arguments
        | otherwise =
            proc "setpriv" $
              [ "--reuid=" <> show owner
              , "--regid=" <> show group
              , "--clear-groups"
              , "--"
              , command
              ]
                <> arguments
    code <- runProcess (setWorkingDir ("/proc/self/fd" </> show fd) process)
    unless (code == ExitSuccess) (throwM (ChildFailed code))
 where
  -- 起動したコマンドへ、開いたディレクトリを引き継がない。
  -- 作業ディレクトリへの移動はコマンドに置き換わる前なので、それまでは開いている。
  flags = defaultFileFlags{directory = True, nofollow = True, cloexec = True}

-- | 権限を落とす時に使う、ユーザの主グループ。
--
-- ディレクトリのグループは使わない。
-- setgidの付いたディレクトリの中に作ったディレクトリは親のグループを引き継ぐので、
-- 所有者が属していないグループの権限で掃除することになってしまう。
--
-- ユーザの一覧に無いuidは主グループが分からない。
-- 消したユーザや、他のホストから持ってきたデータの所有者が当たる。
-- その時は、どのグループの権限も足さないように`nogroup`にする。
-- ゴミ箱の中身は所有者のものなので、グループの権限が無くても掃除できる。
primaryGroupOf :: (MonadUnliftIO m) => UserID -> m GroupID
primaryGroupOf user =
  either (const nogroup) userGroupID <$> tryIO (liftIO (getUserEntryForID user))
 where
  nogroup = 65534
