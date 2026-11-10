-- | 最初のcloneで使うpartial cloneのフィルタ。
module GitRepoSubscribe.PartialCloneFilter
  ( PartialCloneFilter
  , parsePartialCloneFilter
  , filterArgument
  ) where

import GitRepoSubscribe.Failure (PartialCloneFilterError (..))
import GitRepoSubscribe.UnsafeCharacter (hasUnsafeCharacter)
import Himari

-- | Gitの引数1つとして安全に渡せる、空でないpartial cloneのフィルタ。
--
-- 構築子は公開せず、検証を通った値しか作れないようにする。
-- フィルタの文法はGitが検証する。
-- ここが保証するのは、値が複数の引数に見えないことだけである。
newtype PartialCloneFilter = PartialCloneFilter Text
  deriving stock (Eq, Show)

-- | Gitへ渡す`--filter=<値>`の引数。
filterArgument :: PartialCloneFilter -> Text
filterArgument (PartialCloneFilter value) = "--filter=" <> value

-- | partial cloneのフィルタを検証する。
parsePartialCloneFilter :: Text -> Either PartialCloneFilterError PartialCloneFilter
parsePartialCloneFilter value
  | value == "" = Left EmptyFilter
  | hasUnsafeCharacter value = Left FilterUnsafeCharacter
  | otherwise = Right (PartialCloneFilter value)
