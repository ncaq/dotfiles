-- | `niks3-push-ncaq`の、設定の読み取りから終了までのテスト。
module Spec.Niks3.CliSpec (tests) where

import Data.Text (isInfixOf)
import Fixture (failingSops, recordingSops, runCapturing, variables, withSecretsFile)
import Himari
import NixCachePushNcaq.Niks3.Cli (runWith)
import NixCachePushNcaq.Niks3.Command (Niks3 (..))
import NixCachePushNcaq.Niks3.ServerUrl (ServerUrl)
import Test.Sandwich

-- | 偽の`niks3`が受け取った呼び出し。
data Push = Push
  { tokenFile :: FilePath
  , token :: String
  -- ^ 呼ばれた時点でトークンのファイルに書かれていた中身。
  , serverUrl :: ServerUrl
  , arguments :: [String]
  }
  deriving stock (Eq, Show)

-- | 呼び出しを記録して、指定の終了コードで転送を終える偽の`niks3`。
recordingNiks3 :: (MonadIO m) => IORef [Push] -> ExitCode -> Niks3 m
recordingNiks3 calls exitCode =
  Niks3
    { push = \tokenFile serverUrl arguments -> do
        token <- liftIO (readFile tokenFile)
        exitCode <$ modifyIORef' calls (<> [Push{..}])
    }

-- | シークレットファイルと一時ファイルの置き場所を指す、環境変数を引く関数。
--
-- 一時ファイルはシークレットファイルと同じディレクトリに置かせる。
secretsAt :: FilePath -> Text -> Maybe Text
secretsAt path =
  variables
    [ ("NIKS3_PUSH_NCAQ_SECRETS_FILE", convert path)
    , ("NIKS3_PUSH_NCAQ_SERVER_URL", "https://niks3.example.com/")
    , ("XDG_RUNTIME_DIR", convert (takeDirectory path))
    ]

-- | 読まないはずの標準入力が読まれた。
data InputRead = InputRead
  deriving stock (Eq, Show)

instance Exception InputRead

-- | 読まれたら失敗する標準入力。読まないことを確かめるために使う。
unreadInput :: (MonadThrow m) => m Text
unreadInput = throwM InputRead

tests :: TopSpec
tests = describe "runWith" do
  it "引数があれば標準入力を読まずに、復号したトークンのファイルと引数を転送へ渡す" do
    withSecretsFile \path -> do
      decrypts <- newIORef []
      pushes <- newIORef []
      let args = ["/nix/store/a", "/nix/store/b"]
      runCapturing
        ( runWith
            (recordingSops decrypts)
            (recordingNiks3 pushes ExitSuccess)
            (secretsAt path)
            unreadInput
            args
        )
        >>= (`shouldBe` (Right (), []))
      readIORef decrypts >>= (`shouldBe` [("api_token", path)])
      calls <- readIORef pushes
      fmap (\call -> (call.token, call.serverUrl, call.arguments)) calls
        `shouldBe` [("token-example", "https://niks3.example.com/", args)]
      fmap (\call -> takeDirectory call.tokenFile) calls `shouldBe` [takeDirectory path]
  it "引数が無ければ標準入力のstoreパスを転送へ渡す" do
    withSecretsFile \path -> do
      decrypts <- newIORef []
      pushes <- newIORef []
      runCapturing
        ( runWith
            (recordingSops decrypts)
            (recordingNiks3 pushes ExitSuccess)
            (secretsAt path)
            (pure "/nix/store/a\n/nix/store/b\n")
            []
        )
        >>= (`shouldBe` (Right (), []))
      readIORef pushes
        >>= (`shouldBe` [["/nix/store/a", "/nix/store/b"]]) . fmap (\call -> call.arguments)
  it "転送が終わったらトークンのファイルを消す" do
    withSecretsFile \path -> do
      decrypts <- newIORef []
      pushes <- newIORef []
      _ <-
        runCapturing
          ( runWith
              (recordingSops decrypts)
              (recordingNiks3 pushes ExitSuccess)
              (secretsAt path)
              unreadInput
              ["/nix/store/a"]
          )
      listDirectory (takeDirectory path) >>= (`shouldBe` [takeFileName path])
  it "転送が失敗したらトークンのファイルを消して、その終了コードで終わる" do
    withSecretsFile \path -> do
      decrypts <- newIORef []
      pushes <- newIORef []
      runCapturing
        ( runWith
            (recordingSops decrypts)
            (recordingNiks3 pushes (ExitFailure 3))
            (secretsAt path)
            unreadInput
            ["/nix/store/a"]
        )
        >>= (`shouldBe` (Left (ExitFailure 3), []))
      listDirectory (takeDirectory path) >>= (`shouldBe` [takeFileName path])
  it "シークレットファイルが無ければ復号も標準入力も使わずに理由を出して1で終わる" do
    withSecretsFile \existing -> do
      let path = existing <> ".missing"
      decrypts <- newIORef []
      pushes <- newIORef []
      (result, logs) <-
        runCapturing
          ( runWith
              (recordingSops decrypts)
              (recordingNiks3 pushes ExitSuccess)
              (secretsAt path)
              unreadInput
              []
          )
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      filter (isInfixOf (convert path)) logs `shouldBe` logs
      readIORef decrypts >>= (`shouldBe` [])
      readIORef pushes >>= (`shouldBe` [])
  it "復号が失敗したら転送を呼ばずに理由を出して1で終わる" do
    withSecretsFile \path -> do
      pushes <- newIORef []
      (result, logs) <-
        runCapturing
          (runWith failingSops (recordingNiks3 pushes ExitSuccess) (secretsAt path) unreadInput [])
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      filter (isInfixOf (convert path)) logs `shouldBe` logs
      readIORef pushes >>= (`shouldBe` [])
  it "設定が揃わなければ理由を出して1で終わる" do
    decrypts <- newIORef []
    pushes <- newIORef []
    (result, logs) <-
      runCapturing
        ( runWith
            (recordingSops decrypts)
            (recordingNiks3 pushes ExitSuccess)
            (variables [])
            unreadInput
            []
        )
    result `shouldBe` Left (ExitFailure 1)
    length logs `shouldBe` 1
    filter (isInfixOf "NIKS3_PUSH_NCAQ_SECRETS_FILE") logs `shouldBe` logs
    readIORef decrypts >>= (`shouldBe` [])
    readIORef pushes >>= (`shouldBe` [])
