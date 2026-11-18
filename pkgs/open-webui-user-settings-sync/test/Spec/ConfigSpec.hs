-- | 設定の環境変数の読み方のテスト。
module Spec.ConfigSpec (tests) where

import Himari
import Test.Sandwich
import UserSettingsSync.Config (Config (..), configFrom)
import UserSettingsSync.Failure (ConfigFailure (..))

-- | 省けない変数が揃っている設定。
complete :: [(Text, Text)]
complete =
  [ ("OPEN_WEBUI_URL", "https://open-webui.example.ts.net")
  , ("OPEN_WEBUI_DECLARED_SETTINGS_FILE", "/nix/store/settings.json")
  , ("OPEN_WEBUI_DECLARED_PROFILE_FILE", "/nix/store/profile.json")
  , ("OPEN_WEBUI_PROFILE_IMAGE_FILE", "/nix/store/favicon.webp")
  ]

tests :: TopSpec
tests = describe "configFrom" do
  it "揃っていれば読む" do
    configFrom (`lookup` complete)
      `shouldBe` Right
        Config
          { url = "https://open-webui.example.ts.net"
          , declaredSettingsFile = "/nix/store/settings.json"
          , systemPromptFile = Nothing
          , declaredProfileFile = "/nix/store/profile.json"
          , profileImageFile = "/nix/store/favicon.webp"
          }
  it "システムプロンプトのファイルがあれば読む" do
    promptFileWith "/nix/store/prompt.md" `shouldBe` Right (Just "/nix/store/prompt.md")
  it "システムプロンプトのファイルが空なら、無いのと同じに扱う" do
    promptFileWith "" `shouldBe` Right Nothing
  for_ (fst <$> complete) \variable -> do
    it (convert variable <> "が無ければ失敗にする") do
      configFrom (`lookup` filter ((/= variable) . fst) complete)
        `shouldBe` Left (MissingVariable variable)
    it (convert variable <> "が空でも失敗にする") do
      configFrom (`lookup` ((variable, "") : complete)) `shouldBe` Left (MissingVariable variable)
 where
  -- システムプロンプトのファイルの変数をこの値にした時に、読み取られるパス。
  promptFileWith value =
    (.systemPromptFile)
      <$> configFrom (`lookup` (("OPEN_WEBUI_SYSTEM_PROMPT_FILE", value) : complete))
