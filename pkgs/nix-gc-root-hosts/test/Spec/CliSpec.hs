-- | 設定の読み取りから終了までのテスト。
module Spec.CliSpec (tests) where

import Data.Text (isInfixOf)
import Himari
import NixGcRootHosts.Cli (runWith)
import NixGcRootHosts.Nix (Nix (..))
import Test.Sandwich

-- | ログを端末へ出さずに集めて、結果と共に返す。
runCapturing :: (MonadIO m) => Himari SimpleEnv a -> m (Either ExitCode a, [Text])
runCapturing action = do
  logs <- newIORef []
  result <-
    runSimpleEnvWith
      (\_ _ _ message -> modifyIORef' logs (<> [convert (fromLogStr message)]))
      (try action)
  (result,) <$> readIORef logs

-- | 1つのホストだけがあり、out-linkを張る時の終了コードを指定できる偽の`nix`。
nixLinking :: (MonadIO m) => ExitCode -> Nix m
nixLinking exitCode =
  Nix
    { attrNames = \_ -> \case
        "nixosConfigurations" -> pure ["bullet"]
        _ -> pure []
    , warmUp = const (pure ExitSuccess)
    , link = \_ _ -> pure exitCode
    }

-- | 一時ディレクトリを状態ディレクトリとして渡す、環境変数を引く関数を作って実行する。
withStateDirectory :: (MonadUnliftIO m) => ((Text -> Maybe Text) -> m a) -> m a
withStateDirectory action =
  withSystemTempDirectory "nix-gc-root-hosts-test" \stateDirectory ->
    action \case
      "STATE_DIRECTORY" -> Just (convert stateDirectory)
      _ -> Nothing

tests :: TopSpec
tests = describe "runWith" do
  it "全て登録できたら成功で終わる" do
    withStateDirectory \lookupVariable ->
      runCapturing (runWith (nixLinking ExitSuccess) lookupVariable)
        >>= (`shouldBe` (Right (), []))
  it "登録できなかったrootがあれば理由を出して1で終わる" do
    withStateDirectory \lookupVariable -> do
      (result, logs) <- runCapturing (runWith (nixLinking (ExitFailure 1)) lookupVariable)
      result `shouldBe` Left (ExitFailure 1)
      length logs `shouldBe` 1
      filter (isInfixOf "nixosConfigurations.bullet") logs `shouldBe` logs
  it "状態ディレクトリの指定が無ければ理由を出して1で終わる" do
    (result, logs) <- runCapturing (runWith (nixLinking ExitSuccess) (const Nothing))
    result `shouldBe` Left (ExitFailure 1)
    length logs `shouldBe` 1
    filter (isInfixOf "STATE_DIRECTORY") logs `shouldBe` logs
