-- | 設定の環境変数の読み方のテスト。
module Spec.ConfigSpec (tests) where

import Himari
import Test.Sandwich
import UserSettingsSync.Config (Config (..), configFrom)
import UserSettingsSync.Failure (ConfigFailure (..))

-- | 揃っている設定。
complete :: [(Text, Text)]
complete =
  [ ("OPEN_WEBUI_URL", "https://open-webui.example.ts.net")
  , ("OPEN_WEBUI_DECLARED_SETTINGS_FILE", "/nix/store/settings.json")
  , ("OPEN_WEBUI_SYSTEM_PROMPT_FILE", "/nix/store/prompt.md")
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
          , systemPromptFile = "/nix/store/prompt.md"
          , declaredProfileFile = "/nix/store/profile.json"
          , profileImageFile = "/nix/store/favicon.webp"
          }
  for_ (fst <$> complete) \variable -> do
    it (convert variable <> "が無ければ失敗にする") do
      configFrom (`lookup` filter ((/= variable) . fst) complete)
        `shouldBe` Left (MissingVariable variable)
    it (convert variable <> "が空でも失敗にする") do
      configFrom (`lookup` ((variable, "") : complete)) `shouldBe` Left (MissingVariable variable)
