-- | `niks3`へ認証トークンを渡すための一時ファイル。
module NixCachePushNcaq.Niks3.TokenFile
  ( systemTokenDirectory
  , tokenDirectoryFrom
  , withTokenFile
  ) where

import Data.Text.IO.Utf8 (hPutStr, readFile)
import Himari hiding (readFile)
import NixCachePushNcaq.AuthToken (AuthToken (..))
import NixCachePushNcaq.Failure (ConfigFailure (..))
import NixCachePushNcaq.MountInfo (Mount, fileSystemOf, parseMountInfo)

-- | このマシンで一時ファイルを置くディレクトリを選ぶ。
--
-- 候補は`XDG_RUNTIME_DIR`、`/dev/shm`、システムの一時ディレクトリの順で、
-- `/proc/self/mountinfo`を読んで実際にtmpfsであるものだけを使う。
-- 一時ディレクトリは、tmpfsにしている環境でだけ選ばれる。
--
-- `XDG_RUNTIME_DIR`が設定されているのに使えなかった時は、警告を出して他の候補を使う。
-- 黙って切り替えると、環境の設定の誤りに気付けない。
systemTokenDirectory
  :: (MonadIO m, MonadLogger m, MonadThrow m) => Maybe FilePath -> m FilePath
systemTokenDirectory runtimeDirectory = do
  mounts <- liftIO (readFile "/proc/self/mountinfo") >>= parseMountInfo
  temporaryDirectory <- getTemporaryDirectory
  directory <-
    tokenDirectoryFrom mounts (toList runtimeDirectory <> ["/dev/shm", temporaryDirectory])
  for_ (mfilter (/= directory) runtimeDirectory) \unused ->
    logWarnN
      ( "XDG_RUNTIME_DIRの"
          <> convert unused
          <> "は存在するtmpfsの上のディレクトリではないので、代わりに"
          <> convert directory
          <> "を使います"
      )
  pure directory

-- | 候補のうち、存在していてtmpfsの上にある最初のディレクトリを選ぶ。
--
-- tmpfsでない場所は、消し損ねた時に平文のトークンがディスクに残るので使わない。
-- 使える候補が無ければ`NoTmpfsDirectory`を投げる。
--
-- シンボリックリンクを辿った先で判定する。返すのは渡された候補のままのパスである。
tokenDirectoryFrom :: (MonadIO m, MonadThrow m) => [Mount] -> [FilePath] -> m FilePath
tokenDirectoryFrom mounts candidates =
  foldr orNext (throwM (NoTmpfsDirectory candidates)) candidates
 where
  -- 使える候補が見つかった時点で返して、後ろの候補は調べない。
  orNext candidate next = onTmpfs candidate >>= bool next (pure candidate)
  onTmpfs candidate = do
    exists <- doesDirectoryExist candidate
    if exists
      then (== Just "tmpfs") . fileSystemOf mounts <$> canonicalizePath candidate
      else pure False

-- | 認証トークンを書いた一時ファイルを作って処理に渡し、処理が終わったら消す。
--
-- `niks3`は環境変数からトークンを受け取らず、引数は`/proc`から他のユーザにも見えるので、
-- `--auth-token-path`に渡すファイルを使う。
-- 環境変数と違って、`niks3`が起動する子プロセスへ引き継がれることも無い。
--
-- ファイルは所有者だけが読み書きできるモードで作られる。
-- 処理が例外で終わった時も消す。
-- SIGKILLで止められた時だけは残るので、tmpfsのディレクトリを渡すのは呼び出し側の責任である。
-- `systemTokenDirectory`で選べる。
--
-- 末尾に改行は付けない。
withTokenFile :: (MonadUnliftIO m) => FilePath -> AuthToken -> (FilePath -> m a) -> m a
withTokenFile directory (AuthToken token) action =
  withTempFile directory "niks3-push-ncaq-token" \path file -> do
    liftIO (hPutStr file token)
    hClose file
    action path
