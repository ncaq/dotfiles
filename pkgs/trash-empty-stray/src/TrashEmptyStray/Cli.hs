-- | コマンドライン引数の解釈と、結果の終了コードへの変換。
--
-- `app/Main.hs`は環境を用意してここを呼ぶだけにする。
--
-- `trash-empty --all-users`が見つけられないゴミ箱を探して掃除する。
--
-- `trash-put`は`os.path.ismount`で親を辿ってボリュームを決めるが、
-- `trash-empty`はマウントの一覧にある決まった種類のファイルシステムの直下しか見ない。
-- そのためCIFS越しに捨てた時に共有の中へ作られた`.Trash-<uid>`は、
-- クライアントからはCIFSが対象外で、
-- サーバからは共有のルートがマウントの直下ではないので、
-- どのホストからも掃除されずに残る。
--
-- 2つのサブコマンドを持つ。
--
-- - `sweep`: 引数の起点の下からゴミ箱を全て探して、1つずつ掃除する。サービスが呼ぶのはこちら
-- - `clean-here`: 今いるディレクトリをゴミ箱として掃除する。`sweep`が自分自身を呼ぶためのもの
--
-- 分けているのは、見つけたゴミ箱を所有者の権限で掃除するためである。
-- `sweep`はゴミ箱ごとに、権限を落とした`clean-here`を起動する。
-- 探し方は`TrashEmptyStray.Search`に、権限の落とし方は`TrashEmptyStray.Owner`に書いてある。
--
-- lensの`argument`はoptparse-applicativeの位置引数と名前がぶつかるので、Himariの側を隠す。
module TrashEmptyStray.Cli
  ( run
  , runWith
  ) where

import Himari hiding (argument)
import Options.Applicative
import TrashEmptyStray.Clean (cleanTrashDir)
import TrashEmptyStray.Owner (runAsOwnerInside)
import TrashEmptyStray.RetentionDays (RetentionDays (..))
import TrashEmptyStray.Search (findTrashDirs)
import TrashEmptyStray.TrashDir (TrashDir (..))

data Operation
  = Sweep RetentionDays [FilePath]
  | -- | 日数と、空になったゴミ箱自体を消す時のパス。
    CleanHere RetentionDays FilePath
  deriving stock (Eq, Show)

-- | 動いている実行ファイル自身を`clean-here`の起動に使って実行する。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [String] -> m ()
run argv = do
  self <- getExecutablePath
  runWith self argv

-- | `clean-here`を起動する時のコマンドを受け取って実行する。
--
-- `sweep`は、掃除できないゴミ箱があっても残りを全て回り、最後に`ExitFailure 1`にする。
-- 1つの壊れたゴミ箱のために、他のゴミ箱が掃除されないままになるのを避ける。
-- 理由はその場でログに出ている。
-- 引数が誤っている時は、使い方を標準エラー出力へ出して`ExitFailure 1`にする。
runWith :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => FilePath -> [String] -> m ()
runWith self argv =
  liftIO (handleParseResult (execParserPure defaultPrefs parserInfo argv)) >>= \case
    Sweep days roots -> do
      trashDirs <- findTrashDirs roots
      results <- for trashDirs \path -> do
        logInfoN (convert path <> "を掃除します")
        result <- tryAny (runAsOwnerInside path self (cleanHereArguments days path))
        for_ (result ^? _Left) (report path)
        pure result
      unless (all isRight results) (throwM (ExitFailure 1))
    CleanHere days path ->
      cleanTrashDir days TrashDir{inside = ".", self = path} `catchAny` \exception -> do
        report path exception
        throwM (ExitFailure 1)
 where
  report :: (MonadLogger m) => FilePath -> SomeException -> m ()
  -- `SomeException`のまま表示するとバックトレースまで付くので、中の例外を表示する。
  report path (SomeException exception) =
    logErrorN (convert path <> "を掃除できませんでした: " <> convert (displayException exception))

-- | `clean-here`として解釈される引数を組み立てる。
cleanHereArguments :: RetentionDays -> FilePath -> [String]
cleanHereArguments (RetentionDays days) path = ["clean-here", "--days", show days, "--self", path]

parserInfo :: ParserInfo Operation
parserInfo =
  info
    (operationParser <**> helper)
    (progDesc "Empty trash directories that trash-empty --all-users cannot find")

operationParser :: Parser Operation
operationParser =
  hsubparser
    ( command
        "sweep"
        ( info
            (Sweep <$> daysOption <*> many rootArgument)
            (progDesc "Find trash directories under the roots and empty each one as its owner")
        )
        <> command
          "clean-here"
          ( info
              (CleanHere <$> daysOption <*> selfOption)
              (progDesc "Empty the trash directory at the current directory")
          )
    )

rootArgument :: Parser FilePath
rootArgument = strArgument (metavar "ROOT" <> help "Directory to search under")

selfOption :: Parser FilePath
selfOption =
  strOption (long "self" <> metavar "PATH" <> help "Path to remove the trash directory itself by")

daysOption :: Parser RetentionDays
daysOption =
  RetentionDays
    <$> option
      auto
      (long "days" <> metavar "DAYS" <> help "Remove entries trashed more than DAYS days ago")
