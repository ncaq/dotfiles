-- | 既存のworktreeに設定されているリモート。
module GitRepoSubscribe.ConfiguredRemote
  ( ConfiguredRemote (..)
  , configuredAs
  ) where

import GitRepoSubscribe.RemoteUrl (RemoteUrl, remoteUrlText)
import Himari

-- | 既存のGitの設定から読んだ、中身を解釈しないリモートの場所。
--
-- Gitが返した綴りを変えずに包む。
-- 人が設定したものなので、購読のURLとしては受け付けない形のこともある。
newtype ConfiguredRemote = ConfiguredRemote Text
  deriving stock (Eq, Show)

-- | 既存の設定のリモートが、購読の設定のURLと同じ綴りか。
configuredAs :: RemoteUrl -> ConfiguredRemote -> Bool
configuredAs expected (ConfiguredRemote actual) = remoteUrlText expected == actual
