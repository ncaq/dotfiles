-- | 設定の環境変数の読み方のテスト。
module Spec.ConfigSpec (tests) where

import GarageSetup.Config (Config (..), configFrom)
import GarageSetup.Failure (ConfigFailure (..))
import Himari
import Test.Sandwich

-- | 揃っている設定。
complete :: [(Text, Text)]
complete =
  [ ("GARAGE_SETUP_NAME", "niks3-public")
  , ("GARAGE_SETUP_API", "http://[fdf2:a855:5a3f:100::61]:3903")
  , ("GARAGE_SETUP_ADMIN_TOKEN_FILE", "/run/secrets/garage-admin-token")
  , ("RUNTIME_DIRECTORY", "/run/garage-setup/niks3-public")
  ]

tests :: TopSpec
tests = describe "configFrom" do
  it "揃っていれば読む" do
    configFrom (`lookup` complete)
      `shouldBe` Right
        Config
          { name = "niks3-public"
          , api = "http://[fdf2:a855:5a3f:100::61]:3903"
          , adminTokenFile = "/run/secrets/garage-admin-token"
          , runtimeDirectory = "/run/garage-setup/niks3-public"
          }
  for_ (fst <$> complete) \variable -> do
    it (convert variable <> "が無ければ失敗にする") do
      configFrom (`lookup` filter ((/= variable) . fst) complete)
        `shouldBe` Left (MissingVariable variable)
    it (convert variable <> "が空でも失敗にする") do
      configFrom (`lookup` ((variable, "") : complete)) `shouldBe` Left (MissingVariable variable)
