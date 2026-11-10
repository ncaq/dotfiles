-- | GarageのAdmin APIのトークン。
module GarageSetup.AdminToken
  ( AdminToken (..)
  , readAdminToken
  ) where

import Data.ByteString qualified as B
import Data.Text qualified as T
import Himari

-- | `Show`は中身を伏せる。
newtype AdminToken = AdminToken Text
  deriving stock (Eq)
  deriving newtype (IsString)

instance Show AdminToken where
  show _ = "AdminToken <redacted>"

-- | ファイルからトークンを読む。前後の空白と改行は落とす。
readAdminToken :: (MonadIO m) => FilePath -> m AdminToken
readAdminToken path = AdminToken . T.strip . convert <$> liftIO (B.readFile path)
