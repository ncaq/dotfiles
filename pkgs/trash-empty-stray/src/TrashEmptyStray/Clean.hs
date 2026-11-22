-- | ゴミ箱1つの掃除。
module TrashEmptyStray.Clean
  ( cleanTrashDir
  ) where

import Himari
import System.IO.Error (isDoesNotExistError, isPermissionError)
import System.Posix.Files (fileOwner, getSymbolicLinkStatus, isDirectory)
import System.Posix.User (getEffectiveUserID)
import TrashEmptyStray.Failure (CleanFailure (..))
import TrashEmptyStray.RetentionDays (RetentionDays (..))
import TrashEmptyStray.TrashDir (TrashDir (..))

-- | 期限切れのエントリを消して、空になったらゴミ箱ごと消す。
--
-- 期限の判定とエントリの削除は`trash-empty`に任せる。
--
-- 空になったゴミ箱をゴミ箱ごと消すのは、
-- うっかり作られた場所に空のディレクトリが残り続けて、手で消して回ることになるためである。
-- 捨てている最中のゴミ箱を壊さないように、
-- `.trashinfo`が先に書かれる`info`が空の時だけ`files`へ進む。
--
-- `info`か`files`が、掃除する者の所有する本物のディレクトリでない時は、警告を出して何もしない。
cleanTrashDir
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => RetentionDays -> TrashDir -> m ()
cleanTrashDir (RetentionDays days) trashDir = do
  genuine <- isOwnDirectoryOrMissing info &&^ isOwnDirectoryOrMissing files
  if genuine
    then do
      code <- runProcess (proc "trash-empty" ["-f", show days, "--trash-dir", trashDir.inside])
      unless (code == ExitSuccess) (throwM (TrashEmptyFailed code))
      emptied <- removeIfEmpty info &&^ removeIfEmpty files
      when emptied (void (removeIfEmpty trashDir.self))
    else
      logWarnN
        ( convert trashDir.self
            <> "は、infoかfilesが掃除する者の所有するディレクトリではないので掃除しません"
        )
 where
  info = trashDir.inside </> "info"
  files = trashDir.inside </> "files"
  first &&^ second =
    first >>= \case
      True -> second
      False -> pure False

-- | 掃除する者自身が所有する本物のディレクトリか、存在しない時に真を返す。
--
-- `trash-empty`は`info`や`files`がシンボリックリンクでも辿って中身を消す。
-- 所有者の権限で掃除していれば、消せるのは所有者が自分で消せるものだけに収まる。
-- それでも掃除する前に確かめるのは、その前提が崩れる場合に備えるためである。
-- rootが所有するゴミ箱は「他の者には中を書き換えられない」としてrootのまま掃除するが、
-- 誰でも書き込める権限で残ったroot所有のディレクトリや、
-- uidの対応付け無しにホストの場所へ書けるコンテナのrootがあると、中にリンクを置かれてしまう。
--
-- 当てはまらないゴミ箱は、失敗にせずに警告を出して飛ばす。
-- わざと壊したゴミ箱を置くだけで、掃除のユニットを毎日失敗させられるのを避ける。
isOwnDirectoryOrMissing :: (MonadUnliftIO m) => FilePath -> m Bool
isOwnDirectoryOrMissing path =
  tryIO (liftIO (getSymbolicLinkStatus path)) >>= \case
    Left exception -> pure (isDoesNotExistError exception)
    Right status -> do
      effective <- liftIO getEffectiveUserID
      pure (isDirectory status && fileOwner status == effective)

-- | 空のディレクトリを消す。消えたか、元から無い時に真を返す。
--
-- 空でない時は何もせずに偽を返す。
-- それ以外の理由で消せない時は、理由をログに出して偽を返す。
--
-- 権限が無くて消せない時は警告にしない。
-- ゴミ箱は所有者の権限で掃除するので、
-- マウントポイントの直下のように親がroot所有の場所では、空になったゴミ箱自体を消せないのが正常である。
-- 警告にすると、そのゴミ箱が空である限り毎日同じ警告が出続ける。
removeIfEmpty :: (MonadLogger m, MonadUnliftIO m) => FilePath -> m Bool
removeIfEmpty path =
  tryIO (removeDirectory path) >>= \case
    Right () -> True <$ logInfoN (convert path <> "を消しました")
    Left exception
      | isDoesNotExistError exception -> pure True
      | isPermissionError exception ->
          False <$ logInfoN (convert path <> "は親に書き込めないので残します")
      | otherwise ->
          doesDirectoryNonEmpty >>= \case
            True -> pure False
            False ->
              False
                <$ logWarnN
                  (convert path <> "を消せませんでした: " <> convert (displayException exception))
 where
  -- 空でないために消せなかったのかを、エラーの種類ではなく中身で確かめる。
  -- 空でないことを表すエラーの種類は、他の理由と共有されているためである。
  doesDirectoryNonEmpty = either (const False) (not . null) <$> tryIO (listDirectory path)
