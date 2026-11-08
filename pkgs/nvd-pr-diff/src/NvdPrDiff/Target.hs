-- | 投稿先のPRと、そこへ届くための情報。環境変数から受け取る。
--
-- GitHub Actionsのワークフローが渡すものをそのまま受け取る。
-- 揃えれば手元からも同じように動く。
--
-- * `BASE_REF`: PRのベースブランチ名。
-- * `PR_NUMBER`: PR番号。
-- * `GITHUB_REPOSITORY`: `owner/repo`。
-- * `GH_TOKEN`: PRコメントを投稿できるGitHubのトークン。
module NvdPrDiff.Target
  ( Target (..)
  , TargetFailure (..)
  , targetFrom
  , readTarget
  ) where

import Himari

data Target = Target
  { baseRef :: Text
  , prNumber :: Int
  , repository :: Text
  , token :: Text
  }
  deriving stock (Eq, Show)

-- | 投稿先を揃えられない理由。
data TargetFailure
  = -- | 必要な環境変数が無い。その名前。
    MissingVariable Text
  | -- | PR番号が数ではない。その生の値。
    InvalidPrNumber Text
  deriving stock (Eq, Show)

instance Exception TargetFailure where
  displayException = \case
    MissingVariable name -> "環境変数" <> convert name <> "が必要です"
    InvalidPrNumber raw -> "PR_NUMBERが数ではありません: " <> convert raw

-- | 環境変数を引く関数から投稿先を組み立てる。
--
-- GitHub Actionsは`${{ github.base_ref }}`のように値の無い式を空文字列で渡すので、
-- 空は無いのと同じに扱う。
targetFrom :: (Text -> Maybe Text) -> Either TargetFailure Target
targetFrom lookupVariable =
  Target
    <$> require "BASE_REF"
    <*> (require "PR_NUMBER" >>= number)
    <*> require "GITHUB_REPOSITORY"
    <*> require "GH_TOKEN"
 where
  require name =
    maybe (Left (MissingVariable name)) Right (mfilter (/= mempty) (lookupVariable name))
  number raw = maybe (Left (InvalidPrNumber raw)) Right (readMay (convert raw))

-- | 実際の環境変数から投稿先を読む。
readTarget :: (MonadIO m, MonadThrow m) => m Target
readTarget = do
  environment <- getEnvironment
  either throwM pure (targetFrom \name -> convert <$> lookup (convert name) environment)
