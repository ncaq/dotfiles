-- | 例外として投げる失敗の型。
--
-- 値の検証で落ちた理由と、Gitの実行が続けられない形で失敗した理由を置く。
-- 安全に更新できないだけの想定のうちの状態は失敗ではないので、
-- ここではなく`GitRepoSubscribe.Outcome`の`SkipReason`で表す。
module GitRepoSubscribe.Failure
  ( RemoteUrlError (..)
  , WorktreePathError (..)
  , PartialCloneFilterError (..)
  , BranchNameError (..)
  , CommitIdError (..)
  , GitFailure (..)
  ) where

import Data.Text.Encoding.Error (UnicodeException)
import Himari

-- | リモートのURLとして受け付けられない理由。
data RemoteUrlError
  = -- | URLとして読めない。
    InvalidUrlSyntax
  | -- | 対応していないスキーム。そのスキーム。
    UnsupportedScheme Text
  | -- | 接続先のホストが無い。`file`はホストが空でもよいが、オーソリティごと無いものは拒否する。
    UrlMissingHost
  | -- | パスワードが埋め込まれている。
    UrlPassword
  | -- | HTTPSかfileのURLにユーザ名が埋め込まれている。
    UrlUsername
  | -- | 空白か制御文字を含む。
    UrlUnsafeCharacter
  | -- | バックスラッシュを含む。GitとURLのパーサで解釈が分かれる。
    UrlBackslash
  deriving stock (Eq, Show)

instance Exception RemoteUrlError where
  displayException = \case
    InvalidUrlSyntax -> "Git remote URL is not a valid absolute URL"
    UnsupportedScheme scheme ->
      "unsupported Git remote URL scheme `" <> convert scheme <> "`; expected https, ssh, or file"
    UrlMissingHost -> "Git remote URL must name a host after `//`"
    UrlPassword -> "Git remote URL must not contain a password"
    UrlUsername -> "HTTPS and file Git remote URLs must not contain a username"
    UrlUnsafeCharacter -> "Git remote URL must not contain whitespace or control characters"
    UrlBackslash -> "Git remote URL must not contain backslashes"

-- | worktreeのパスとして受け付けられない理由。
data WorktreePathError
  = -- | 相対パス。
    RelativePath
  | -- | ファイルシステムのルート。
    RootPath
  | -- | `..`を含む。
    NotNormalizedPath
  deriving stock (Eq, Show)

instance Exception WorktreePathError where
  displayException = \case
    RelativePath -> "worktree path must be absolute"
    RootPath -> "worktree path must not be the filesystem root"
    NotNormalizedPath -> "worktree path must not contain `..` components"

-- | partial cloneのフィルタとして受け付けられない理由。
data PartialCloneFilterError
  = -- | 空。
    EmptyFilter
  | -- | 空白か制御文字を含む。
    FilterUnsafeCharacter
  deriving stock (Eq, Show)

instance Exception PartialCloneFilterError where
  displayException = \case
    EmptyFilter -> "partial clone filter must not be empty"
    FilterUnsafeCharacter ->
      "partial clone filter must not contain whitespace or control characters"

-- | Gitの参照名の規則を満たさないブランチ名。その生の値。
newtype BranchNameError = BranchNameError Text
  deriving stock (Eq, Show)

instance Exception BranchNameError where
  displayException (BranchNameError value) = "invalid branch name: " <> convert value

-- | 省略されていないオブジェクトIDとして読めなかった値。
newtype CommitIdError = CommitIdError Text
  deriving stock (Eq, Show)

instance Exception CommitIdError where
  displayException (CommitIdError value) = "Git returned an invalid commit ID: " <> convert value

-- | Gitの実行が続けられない形で失敗した理由。
data GitFailure
  = -- | 成功が必要なGitのコマンドが失敗した。その引数と終了コード。
    GitFailed [String] ExitCode
  | -- | Gitの出力がUTF-8ではなかった。その引数と復号の誤り。
    InvalidGitOutput [String] UnicodeException
  deriving stock (Eq, Show)

instance Exception GitFailure where
  displayException = \case
    GitFailed args code -> "git " <> unwords args <> " failed with " <> show code
    InvalidGitOutput args reason ->
      "git " <> unwords args <> " returned non-UTF-8 output: " <> displayException reason
