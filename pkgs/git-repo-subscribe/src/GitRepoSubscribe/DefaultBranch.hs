-- | リモートのデフォルトブランチの問い合わせ。
module GitRepoSubscribe.DefaultBranch
  ( parseDefaultBranch
  , queryDefaultBranch
  ) where

import Data.Text (splitOn, stripPrefix, stripSuffix)
import GitRepoSubscribe.BranchName (BranchName, parseBranchName)
import GitRepoSubscribe.Failure (BranchNameError)
import GitRepoSubscribe.Git (ErrorOutput (..), gitOptionalText)
import GitRepoSubscribe.RemoteUrl (RemoteUrl, remoteUrlText)
import Himari

-- | `git ls-remote --symref`の出力から、`HEAD`が指すデフォルトブランチを読む。
--
-- `HEAD`がブランチを指していなければ`Nothing`。
parseDefaultBranch :: Text -> Either BranchNameError (Maybe BranchName)
parseDefaultBranch =
  traverse parseBranchName
    . headMay
    . mapMaybe (stripPrefix "ref: refs/heads/" >=> stripSuffix "\tHEAD")
    . splitOn "\n"

-- | リモートへ問い合わせて、`git ls-remote --symref`の出力を返す。
--
-- 届かない時は`Nothing`。通信の不調は想定のうちなので失敗にはしない。
queryDefaultBranch :: (MonadIO m, MonadThrow m) => RemoteUrl -> m (Maybe Text)
queryDefaultBranch url =
  gitOptionalText Inherited ["ls-remote", "--symref", "--", convert (remoteUrlText url), "HEAD"]
