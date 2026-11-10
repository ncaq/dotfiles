-- | Gitの子プロセスの起動。
--
-- 呼び出し元のリポジトリやユーザの設定に結果を左右されないように、
-- 環境変数と作業ディレクトリを固定して起動する。
module GitRepoSubscribe.Git
  ( ErrorOutput (..)
  , inWorktree
  , gitRun
  , gitChecked
  , gitText
  , gitOptionalText
  ) where

import Data.Text (dropWhileEnd)
import Data.Text.Lazy.Encoding (decodeUtf8')
import GitRepoSubscribe.Failure (GitFailure (..))
import GitRepoSubscribe.Git.Environment (gitEnvironment)
import Himari
import System.Process.Typed qualified

-- | Gitの標準エラー出力をどうするか。
data ErrorOutput
  = -- | このプロセスの標準エラー出力へそのまま流す。
    Inherited
  | -- | 捨てる。失敗が想定のうちで、Gitの説明が雑音になる時に使う。
    Discarded
  deriving stock (Eq, Show)

-- | 指定のworktreeを対象にする引数を前に付ける。
inWorktree :: FilePath -> [String] -> [String]
inWorktree path args = ["-C", path] <> args

-- | 固定した環境でGitを起動する設定。
--
-- 作業ディレクトリは`/`にして、呼び出し元がいるリポジトリを拾わせない。
gitProcess :: (MonadIO m) => [String] -> m (ProcessConfig () () ())
gitProcess args = do
  inherited <- getEnvironment
  pure . setWorkingDir "/" . System.Process.Typed.setEnv (gitEnvironment inherited) $
    proc "git" args

-- | Gitを実行して終了コードを返す。出力はそのまま流す。
gitRun :: (MonadIO m) => [String] -> m ExitCode
gitRun = gitProcess >=> runProcess

-- | Gitを実行して、失敗したら例外にする。出力はそのまま流す。
gitChecked :: (MonadIO m, MonadThrow m) => [String] -> m ()
gitChecked args = do
  code <- gitRun args
  unless (code == ExitSuccess) (throwM (GitFailed args code))

-- | Gitを実行して、標準出力を末尾の改行を除いた文字列として返す。失敗したら例外にする。
gitText :: (MonadIO m, MonadThrow m) => [String] -> m Text
gitText args = gitCapture Inherited args >>= either (throwM . GitFailed args) pure

-- | Gitを実行して、成功したら標準出力を末尾の改行を除いた文字列として返す。
--
-- 失敗が「無い」ことを表すコマンドに使う。
gitOptionalText :: (MonadIO m, MonadThrow m) => ErrorOutput -> [String] -> m (Maybe Text)
gitOptionalText errorOutput args = preview _Right <$> gitCapture errorOutput args

-- | Gitを実行して、標準出力か失敗の終了コードを返す。
gitCapture :: (MonadIO m, MonadThrow m) => ErrorOutput -> [String] -> m (Either ExitCode Text)
gitCapture errorOutput args = do
  config <- gitProcess args
  (code, out) <- readProcessStdout case errorOutput of
    Inherited -> config
    Discarded -> setStderr nullStream config
  if code == ExitSuccess
    then
      either
        (throwM . InvalidGitOutput args)
        (pure . Right . dropWhileEnd (\c -> c == '\n' || c == '\r') . convert)
        (decodeUtf8' out)
    else pure (Left code)
