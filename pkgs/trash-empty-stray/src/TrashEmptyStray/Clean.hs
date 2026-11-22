-- | ゴミ箱1つの掃除。
module TrashEmptyStray.Clean
  ( cleanTrashDir
  ) where

import Himari
import System.IO.Error (isDoesNotExistError, isPermissionError)
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
cleanTrashDir
  :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => RetentionDays -> TrashDir -> m ()
cleanTrashDir (RetentionDays days) trashDir = do
  code <- runProcess (proc "trash-empty" ["-f", show days, "--trash-dir", trashDir.inside])
  unless (code == ExitSuccess) (throwM (TrashEmptyFailed code))
  emptied <-
    removeIfEmpty (trashDir.inside </> "info") &&^ removeIfEmpty (trashDir.inside </> "files")
  when emptied (void (removeIfEmpty trashDir.self))
 where
  first &&^ second =
    first >>= \case
      True -> second
      False -> pure False

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
