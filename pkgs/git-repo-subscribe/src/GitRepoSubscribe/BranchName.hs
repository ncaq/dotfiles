-- | Gitから読んだブランチ名。
module GitRepoSubscribe.BranchName
  ( BranchName
  , parseBranchName
  , branchNameText
  ) where

import Data.Text (isInfixOf, isPrefixOf, isSuffixOf, splitOn)
import GitRepoSubscribe.Failure (BranchNameError (..))
import Himari

-- | Gitの参照名の規則を満たす、`refs/heads/`を除いたローカルブランチ名。
--
-- 構築子は公開せず、検証を通った値しか作れないようにする。
-- 不正な値を後続の`git fetch`のrefspecへ埋め込まないためである。
newtype BranchName = BranchName Text
  deriving stock (Eq, Show)

-- | `refs/heads/`を除いたブランチ名。
branchNameText :: BranchName -> Text
branchNameText (BranchName value) = value

-- | ブランチ名を`git check-ref-format --branch`と同じ規則で検証する。
--
-- 規則は`git-check-ref-format(1)`に列挙されているものである。
-- 検証を純粋関数にしておくために、Gitを呼ばずにここで判定する。
parseBranchName :: Text -> Either BranchNameError BranchName
parseBranchName value
  | valid = Right (BranchName value)
  | otherwise = Left (BranchNameError value)
 where
  valid =
    value /= "@"
      && not ("-" `isPrefixOf` value)
      && not ("." `isSuffixOf` value)
      && not (any (`isInfixOf` value) ["..", "@{"])
      && not (any forbidden (convert value :: String))
      && all validComponent (splitOn "/" value)
  -- 制御文字と空白と、Gitがリビジョンの記法やglobに使う記号。
  forbidden c = c < ' ' || c == '\DEL' || c `elem` (" ~^:?*[\\" :: String)
  -- 空の要素を弾くので、先頭と末尾の`/`と連続した`/`もここで落ちる。
  validComponent component =
    component /= mempty && not ("." `isPrefixOf` component) && not (".lock" `isSuffixOf` component)
