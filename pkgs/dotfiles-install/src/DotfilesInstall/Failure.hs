-- | 想定している失敗の型。
module DotfilesInstall.Failure
  ( UnsupportedArchitecture (..)
  , GitFailure (..)
  ) where

import Himari

-- | home-managerの構成を用意していないアーキテクチャだった。`uname`の`machine`の値。
newtype UnsupportedArchitecture = UnsupportedArchitecture String
  deriving stock (Eq, Show)

instance Exception UnsupportedArchitecture where
  displayException (UnsupportedArchitecture machine) = "未対応のアーキテクチャです: " <> machine

-- | Gitのコマンドが失敗した。その引数と終了コード。
data GitFailure = GitFailed [String] ExitCode
  deriving stock (Eq, Show)

instance Exception GitFailure where
  displayException (GitFailed args code) =
    "git " <> unwords args <> "が" <> show code <> "で失敗しました"
