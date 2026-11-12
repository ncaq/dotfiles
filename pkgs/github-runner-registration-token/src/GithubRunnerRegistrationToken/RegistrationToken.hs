-- | ランナーの登録トークン。
--
-- ランナーの登録にしか使えず、発行から1時間で切れる。
module GithubRunnerRegistrationToken.RegistrationToken
  ( RegistrationToken (..)
  ) where

import Himari

-- | `Show`は中身を伏せる。
newtype RegistrationToken = RegistrationToken Text
  deriving stock (Eq)
  deriving newtype (IsString)

instance Show RegistrationToken where
  show _ = "RegistrationToken <redacted>"

-- | 発行のAPIの応答から読む。`token`の他のフィールドは使わない。
instance FromJSON RegistrationToken where
  parseJSON = withObject "RegistrationToken" \object -> RegistrationToken <$> object .: "token"
