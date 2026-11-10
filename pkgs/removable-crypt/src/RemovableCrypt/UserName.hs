-- | マウントポイントの所有者にするユーザの名前。
module RemovableCrypt.UserName
  ( UserName (..)
  , invokingUser
  ) where

import Himari

newtype UserName = UserName Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)

-- | 環境変数を引く関数から、コマンドを呼んだ人を決める。
--
-- sudo越しに呼ばれるので、`USER`はrootになっている。
-- sudoが残す`SUDO_USER`を先に見る。
invokingUser :: (Text -> Maybe Text) -> Maybe UserName
invokingUser lookupVariable =
  UserName <$> (present "SUDO_USER" <|> present "USER")
 where
  present = mfilter (/= mempty) . lookupVariable
