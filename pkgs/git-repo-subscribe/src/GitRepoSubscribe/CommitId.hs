-- | Gitから読んだコミットのID。
module GitRepoSubscribe.CommitId
  ( CommitId
  , parseCommitId
  ) where

import Data.Char (isHexDigit, toLower)
import GitRepoSubscribe.Failure (CommitIdError (..))
import Himari

-- | SHA-1かSHA-256の、省略されていないGitのオブジェクトID。
--
-- 構築子は公開せず、検証を通った値しか作れないようにする。
-- 16進の大文字と小文字の違いで別物にならないように小文字で持つ。
newtype CommitId = CommitId Text
  deriving stock (Eq, Show)

-- | 16進のオブジェクトIDを検証する。
parseCommitId :: Text -> Either CommitIdError CommitId
parseCommitId value
  | length digits `elem` [40, 64] && all isHexDigit digits =
      Right (CommitId (convert (toLower <$> digits)))
  | otherwise = Left (CommitIdError value)
 where
  digits = convert value :: String
