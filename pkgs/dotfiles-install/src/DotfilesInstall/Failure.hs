-- | 想定している失敗の型。
module DotfilesInstall.Failure
  ( UnsupportedArchitecture (..)
  , GitFailure (..)
  ) where

import Data.Text (unwords)
import Himari hiding (unwords)

-- | home-managerの構成を用意していないアーキテクチャだった。`uname`の`machine`の値。
newtype UnsupportedArchitecture = UnsupportedArchitecture Text
  deriving stock (Eq, Show)

instance Exception UnsupportedArchitecture where
  displayException (UnsupportedArchitecture machine) =
    "未対応のアーキテクチャです: " <> convert machine

-- | Gitのコマンドが失敗した。その引数と終了コード。
data GitFailure = GitFailed [Text] ExitCode
  deriving stock (Eq, Show)

instance Exception GitFailure where
  displayException (GitFailed args code) =
    "git " <> convert (unwords args) <> "が" <> show code <> "で失敗しました"
