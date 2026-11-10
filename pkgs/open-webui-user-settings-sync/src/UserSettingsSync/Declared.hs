-- | 宣言のファイルの読み込み。
module UserSettingsSync.Declared
  ( readDeclaration
  ) where

import Data.ByteString qualified as B
import Himari
import UserSettingsSync.Config (Config (..))
import UserSettingsSync.Failure (DeclarationFailure (..))
import UserSettingsSync.Sync (Declaration (..))

-- | 設定が指すファイルから宣言を読む。
--
-- システムプロンプトをファイルで受け取るのは、値がNixのderivationだからである。
-- Nixの評価の中で中身を開かずに、実行時に読む。
readDeclaration :: (MonadIO m, MonadThrow m) => Config -> m Declaration
readDeclaration config =
  Declaration
    <$> object config.declaredSettingsFile
    <*> (convert <$> bytes config.systemPromptFile)
    <*> object config.declaredProfileFile
    <*> bytes config.profileImageFile
 where
  bytes = liftIO . B.readFile
  object path =
    bytes path >>= either (throwM . UndecodableDeclaration path . convert) pure . eitherDecodeStrict
