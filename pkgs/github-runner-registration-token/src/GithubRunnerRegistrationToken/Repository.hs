-- | ランナーを登録するリポジトリ。
--
-- `ncaq/dotfiles`のように所有者と名前を`/`で繋いだ形で持つ。
module GithubRunnerRegistrationToken.Repository
  ( Repository (..)
  ) where

import Himari

newtype Repository = Repository Text
  deriving stock (Eq, Show)
  deriving newtype (IsString)
