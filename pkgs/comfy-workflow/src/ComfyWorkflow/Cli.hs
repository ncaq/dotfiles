-- | ComfyUIのワークフローを名前付きのオプションで投げるコマンド。
--
-- `local.comfyui.workflows`が宣言しているワークフローごとに、
-- `comfy-<ワークフロー名>`という名前で呼べるようにするための本体である。
--
-- > comfy-anima-standard --positive-prompt "1girl, blue hair" --seed 314
--
-- やっていることは以下だけである。
--
-- * App Modeの入力定義をコマンドラインのオプションにする("ComfyWorkflow.Parameter")
-- * 振り直す約束のseedを配る("ComfyWorkflow.Seed")
-- * 公式の`comfy workflow set-slot`で値を書き込み、`comfy run --print-prompt`でAPI形式にする
-- * `POST /prompt`へ投げて、`comfy jobs wait`で結果を待つ
--
-- UI形式からAPI形式への変換と、ウィジェットの型や選択肢の把握は公式CLIに任せる。
-- どちらも動いているComfyUIの`/object_info`が要るので、
-- `--help`だけでもComfyUIを起こす。
-- ソケットアクティベーションで寝ている時は、
-- オプションの一覧を見るためだけにコンテナが起きることになる。
--
-- 接続先とワークフローの出力ディレクトリは環境変数から取る。
-- どちらもNixの側が知っていて、`cli.nix`がラッパーへ埋め込む。
--
-- 標準出力へ出すのは結果として使えるものだけにする。
-- 保存されたファイルのパスと、`--dry-run`のAPI形式のプロンプトがそれで、
-- 進捗の報告はロガーを通して標準エラー出力へ出す。
module ComfyWorkflow.Cli
  ( run
  , Options (..)
  , optionsParser
  ) where

import ComfyWorkflow.Comfy
  ( ComfyFailure (..)
  , Target (..)
  , comfyJson
  , getHistory
  , parseAuthority
  , postPrompt
  )
import ComfyWorkflow.Parameter (Parameter (..), parameters, parseValue, positiveInt)
import ComfyWorkflow.Prompt
  ( HistoryResult (..)
  , Prompt
  , applySeed
  , fixupPrompt
  , jsonText
  , readHistory
  )
import ComfyWorkflow.Seed (seedTargets)
import ComfyWorkflow.Slot (Slot (..), Slots (..), WidgetType (..))
import ComfyWorkflow.Workflow (Workflow (..), parseWorkflow)
import Data.Text (intercalate)
import Himari
import Options.Applicative
import System.Random (randomRIO)

data Options = Options
  { seed :: Maybe Integer
  , repeatCount :: Int
  , dryRun :: Bool
  , noWait :: Bool
  , values :: [(Parameter, Text)]
  -- ^ 指定されたパラメータと、その生の文字列。
  }

-- | ワークフロー1つ分のコマンドラインを組み立てる。
optionsParser :: Text -> [Parameter] -> ParserInfo Options
optionsParser name params =
  info
    (parser <**> helper)
    (fullDesc <> progDesc ("ComfyUIのワークフロー" <> convert name <> "を実行します。"))
 where
  -- 全体のオプションの名前は"ComfyWorkflow.Parameter"の`reservedFlags`と揃えること。
  -- ここで追加や改名をしてあちらを忘れると、
  -- 同じ名前のウィジェットを持つワークフローでパラメータのフラグと衝突する。
  parser = do
    seed <-
      optional $
        option
          auto
          ( long "seed"
              <> metavar "INT"
              <> help "乱数のseed。省略すると毎回振り直します。UIでfixedにしてあるものには配りません。"
          )
    repeatCount <-
      option
        (eitherReader positiveInt)
        ( long "repeat"
            <> metavar "N"
            <> value 1
            <> help "同じ設定で投げる回数。seedは1ずつずらします。"
        )
    dryRun <-
      switch
        ( long "dry-run"
            <> help
              "投げずにAPI形式のプロンプトを表示します。seedの配布も済ませた、実際に投げる内容です。`--repeat`を付けても最初の1回分だけを表示します。"
        )
    noWait <- switch (long "no-wait" <> help "投入したら結果を待たずに終わります。")
    values <- catMaybes <$> traverse parameterOption params
    pure Options{..}
  parameterOption param =
    optional $
      (param,)
        <$> strOption
          ( long (convert param.flag)
              <> metavar (convert (typeName param.slot.widgetType))
              <> help (convert (describe param))
          )
  describe param =
    mconcat
      [ fromMaybe param.slot.name param.description
      , " (既定: "
      , currentValueText param.slot.currentValue
      , ")"
      , case param.slot.widgetType of
          ComboWidget choices | not (null choices) -> " 選択肢: " <> intercalate ", " choices
          _ -> ""
      ]

typeName :: WidgetType -> Text
typeName IntWidget = "INT"
typeName FloatWidget = "FLOAT"
typeName BooleanWidget = "BOOLEAN"
typeName (ComboWidget _) = "COMBO"
typeName StringWidget = "STRING"
typeName (OtherWidget other) = other

-- | `--help`の既定値の表示。
-- 文字列も引用符付きのJSONとして出すと、
-- 日本語のプロンプトがエスケープされずに読める。
currentValueText :: Value -> Text
currentValueText = jsonText

-- | ワークフローの名前とUI形式のJSONのパスと、残りのコマンドライン引数を受けて実行する。
run :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => Text -> FilePath -> [String] -> m ()
run name workflowPath argv = do
  authority <- fromMaybe "127.0.0.1:8188" <$> lookupEnv "COMFYUI_AUTHORITY"
  target <- either (throwM . ComfyFailure) pure (parseAuthority (convert authority))
  outputDir <- lookupEnv "COMFYUI_OUTPUT_DIR"
  workflowValue <- readWorkflow workflowPath
  workflow <- either (throwM . ComfyFailure) pure (parseWorkflow workflowValue)
  let targetArgs = ["--host", target.host, "--port", convert (show target.port)]
  Slots slots <- comfyJson (["workflow", "slots", convert workflowPath] <> targetArgs)
  params <- either (throwM . ComfyFailure) pure (parameters workflow slots)
  let parserInfo = optionsParser name params
      -- 使い方に出る名前はラッパーの`comfy-<名前>`にする。
      -- 実際の実行ファイルは`comfy-workflow`だが、
      -- 利用者が打つのはラッパーの方である。
      handleResult :: (MonadUnliftIO n) => ParserResult a -> n a
      handleResult result =
        withProgName ("comfy-" <> convert name) (liftIO (handleParseResult result))
      usageError :: Text -> ParserResult a
      usageError reason =
        Failure (parserFailure defaultPrefs parserInfo (ErrorMsg (convert reason)) [])
  options <- handleResult (execParserPure defaultPrefs parserInfo argv)
  overrides <- for options.values \(param, text) ->
    case parseValue param.slot.widgetType text of
      Right parsed -> pure (param.slot.address, parsed)
      Left reason -> handleResult (usageError ("--" <> param.flag <> ": " <> reason))
  baseSeed <- maybe (randomRIO (0, 0xFFFF_FFFF_FFFF)) pure options.seed
  -- 公式CLIによる書き込みと変換は1回だけにする。
  -- `--repeat`で変わるのはseedだけなので、
  -- 変換済みのAPI形式へこちらで差し替えれば、
  -- 回数に関係なく子プロセスの起動と`/object_info`の取得は一定で済む。
  edited <- applyOverrides workflowValue workflowPath targetArgs overrides
  basePrompt <- fixupPrompt workflow.nodes <$> printPrompt targetArgs edited
  let seeds = seedTargets workflow.nodes slots
      seedAddresses = intercalate ", " [nodeId <> "." <> widget | (nodeId, widget) <- seeds]
      prepare seed = applySeed seed seeds basePrompt
  if options.dryRun
    then do
      -- 投げる時と同じ順で同じものを通す。
      -- ここは「何が投げられるのか」を確かめるための出口なので、
      -- 実際に投げる内容と食い違っていては用を成さない。
      liftIO (putStrLn (convert (convert (encodePretty (prepare baseSeed)) :: Text)))
    else do
      -- 先に全件を投入してから順に待つ。
      -- 1件ずつ待ってから次を投げると、
      -- 待ちの間にComfyUIのキューが空になってGPUが遊ぶ。
      -- 投入の順に待つので、seedの割り当ても出力の順も変わらない。
      promptIds <- for [0 .. fromIntegral options.repeatCount - 1] \offset -> do
        let seed = baseSeed + offset
        unless (null seeds) $
          logInfoN ("seed " <> convert (show seed) <> " を " <> seedAddresses <> " へ配りました")
        promptId <- postPrompt target (prepare seed)
        logInfoN ("投入しました: " <> promptId)
        pure promptId
      unless options.noWait $ for_ promptIds \promptId -> do
        waitFor targetArgs promptId
        history <- getHistory target promptId
        result <- either (throwM . ComfyFailure) pure (readHistory promptId history)
        case result of
          Failed reason -> throwM (ComfyFailure ("生成が失敗しました: " <> reason))
          Succeeded files ->
            for_ files \file -> liftIO (putStrLn (maybe file (</> file) outputDir))

readWorkflow :: (MonadIO m, MonadThrow m) => FilePath -> m Value
readWorkflow workflowPath =
  liftIO (eitherDecodeFileStrict workflowPath)
    >>= either (throwM . ComfyFailure . ("ワークフローを読めませんでした: " <>) . convert) pure

-- | `comfy workflow set-slot`で値を書き込んだUI形式のワークフローを返す。
--
-- 書き込むものが無ければ元のまま返す。
-- 公式CLIは上書きの指定が1つも無いと受け付けない。
applyOverrides
  :: (MonadIO m, MonadLogger m, MonadThrow m)
  => Value -> FilePath -> [Text] -> [(Text, Value)] -> m Value
applyOverrides original _ _ [] = pure original
applyOverrides _ workflowPath targetArgs overrides = do
  Edited edited <-
    comfyJson $
      ["workflow", "set-slot", convert workflowPath, "--stdout"]
        <> targetArgs
        -- 値はJSONとして渡す。
        -- 公式CLIは値をまずJSONとして読み、読めなければ文字列として扱うので、
        -- `123`のような文字列を裸で渡すと数値になってしまう。
        <> [address <> "=" <> jsonText override | (address, override) <- overrides]
  pure edited

newtype Edited = Edited Value

instance FromJSON Edited where
  parseJSON = withObject "set-slotの結果" \o -> Edited <$> o .: "workflow_json"

-- | `comfy run --print-prompt`でUI形式をAPI形式へ変換する。
--
-- 公式CLIはファイルのパスしか受け取らないので、一時ファイルへ置く。
printPrompt :: (MonadLogger m, MonadThrow m, MonadUnliftIO m) => [Text] -> Value -> m Prompt
printPrompt targetArgs workflow =
  withSystemTempDirectory "comfy-workflow" \dir -> do
    let path = dir </> "workflow.json"
    writeBinaryFile path (convert (encode workflow))
    Printed prompt <-
      comfyJson $
        ["run", "--workflow", convert path, "--print-prompt", "--timeout", "600"] <> targetArgs
    pure prompt

newtype Printed = Printed Prompt

instance FromJSON Printed where
  parseJSON = withObject "print-promptの結果" \o -> Printed <$> o .: "prompt"

-- | `comfy jobs wait`で終わるまで待つ。
--
-- 動画のワークフローは1本に数十分かかることがあるので上限は長めに取る。
-- ここで待つのを止めても生成そのものは続いているので、
-- 出力はComfyUIの画面か出力ディレクトリで確かめられる。
waitFor :: (MonadIO m, MonadLogger m, MonadThrow m) => [Text] -> Text -> m ()
waitFor targetArgs promptId = do
  Waited jobs <-
    comfyJson $
      ["jobs", "wait", promptId, "--poll-interval", "1", "--timeout", "3600"] <> targetArgs
  case [status | (jobId, status) <- jobs, jobId == promptId] of
    ("completed" : _) -> pure ()
    (status : _) -> throwM (ComfyFailure ("生成が" <> status <> "で終わりました: " <> promptId))
    [] -> throwM (ComfyFailure ("待った結果に" <> promptId <> "がありません"))

newtype Waited = Waited [(Text, Text)]

instance FromJSON Waited where
  parseJSON = withObject "jobs waitの結果" \o -> do
    jobs <- o .: "jobs"
    Waited <$> for jobs (withObject "ジョブ" \job -> (,) <$> job .: "prompt_id" <*> job .: "status")
