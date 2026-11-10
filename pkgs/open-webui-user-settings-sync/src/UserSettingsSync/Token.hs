-- | サインインで得る、APIのトークン。
module UserSettingsSync.Token
  ( Token (..)
  ) where

import Himari

-- | 値ごと`show`してログや例外に出しても中身が漏れないように、`Show`は伏せる。
newtype Token = Token Text
  deriving stock (Eq)
  deriving newtype (IsString)

instance Show Token where
  show _ = "Token <redacted>"
