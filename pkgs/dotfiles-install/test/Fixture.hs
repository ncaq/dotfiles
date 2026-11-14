-- | テストで使う、一時ディレクトリの中のリポジトリ。
module Fixture
  ( withRepository
  , quietly
  , git
  , gitText
  , write
  ) where

import Data.Text (strip)
import Himari

-- | コミットを1つ持つリポジトリを用意して渡し、終わったら一時ディレクトリごと消す。
--
-- ブランチは`master`で、コミットの件名は`feat(test): initial`にする。
-- 追跡しているファイルは`tracked`と`.gitignore`である。
-- 実際のリポジトリと同じく、注入するファイルは`.gitignore`で無視しておく。
withRepository :: (MonadUnliftIO m) => (FilePath -> m a) -> m a
withRepository action = withSystemTempDirectory "dotfiles-install" \repository -> do
  git repository ["init", "--quiet", "--initial-branch=master"]
  write repository "tracked" "initial\n"
  write repository ".gitignore" "/last-commit.json\n"
  git repository ["add", "tracked", ".gitignore"]
  git repository ["commit", "--quiet", "-m", "feat(test): initial"]
  action repository

-- | ログを端末へ出さずに走らせる。
quietly :: (MonadIO m) => Himari SimpleEnv a -> m a
quietly = runSimpleEnvWith \_ _ _ _ -> pure ()

-- | 開発環境の設定に左右されずにコミットできるようにしてGitを起動する設定。
isolated :: FilePath -> [String] -> ProcessConfig () () ()
isolated repository args =
  proc "git" $
    [ "-C"
    , repository
    , "-c"
    , "core.hooksPath=/dev/null"
    , "-c"
    , "user.email=test@example.com"
    , "-c"
    , "user.name=Test"
    , "-c"
    , "commit.gpgsign=false"
    ]
      <> args

-- | 指定のリポジトリでGitを実行する。失敗したら出力を付けた例外になる。
git :: (MonadIO m) => FilePath -> [String] -> m ()
git repository = void . readProcess_ . isolated repository

-- | 指定のリポジトリでGitを実行して、前後の空白を除いた標準出力を返す。
gitText :: (MonadIO m) => FilePath -> [String] -> m Text
gitText repository args = strip . convert <$> readProcessStdout_ (isolated repository args)

-- | リポジトリの中のファイルを書く。
write :: (MonadIO m) => FilePath -> FilePath -> ByteString -> m ()
write repository name = writeBinaryFile (repository </> name)
