-- | 利用者の設定のマージのテスト。
--
-- `settings`列は自由形式のJSONなので、鍵名を書き間違えても、
-- 上流が`settings.ui`の形を変えても、APIはそのまま受け入れて何のエラーも返さない。
-- 合成の結果をここで固定する。
module Spec.SettingsSpec (tests) where

import Fixture
import Himari
import Test.Sandwich
import UserSettingsSync.Settings (currentUi, mergeUi)

declared :: Map Text Value
declared = fields [aesonQQ|{"ctrlEnterToSend": true}|]

tests :: TopSpec
tests = do
  describe "currentUi" do
    it "設定を一度も書いたことが無い利用者のnullは、空として読む" do
      currentUi Null `shouldBe` mempty
    it "uiの中身を取り出す" do
      currentUi [aesonQQ|{"ui": {"models": ["gpt-oss:120b"]}, "other": 1}|]
        `shouldBe` fields [aesonQQ|{"models": ["gpt-oss:120b"]}|]
    it "uiが無ければ空として読む" do
      currentUi [aesonQQ|{"other": 1}|] `shouldBe` mempty
    it "uiがnullなら空として読む" do
      currentUi [aesonQQ|{"ui": null}|] `shouldBe` mempty
  describe "mergeUi" do
    it "今の設定が空なら、宣言とシステムプロンプトだけになる" do
      mergeUi mempty declared "こんにちは\n"
        `shouldBe` fields [aesonQQ|{"ctrlEnterToSend": true, "system": "こんにちは"}|]
    it "宣言した鍵は上書きして、宣言していない鍵は保つ" do
      mergeUi
        (fields [aesonQQ|{"ctrlEnterToSend": false, "models": ["gpt-oss:120b"]}|])
        declared
        "こんにちは\n"
        `shouldBe` fields
          [aesonQQ|{
            "ctrlEnterToSend": true,
            "models": ["gpt-oss:120b"],
            "system": "こんにちは"
          }|]
    it "合成の結果をもう一度合成しても変わらない" do
      let merged = mergeUi (fields [aesonQQ|{"models": ["gpt-oss:120b"]}|]) declared "こんにちは\n"
      mergeUi merged declared "こんにちは\n" `shouldBe` merged
    it "UIから書き換えられたシステムプロンプトを宣言へ戻す" do
      mergeUi (fields [aesonQQ|{"system": "書き換えた"}|]) mempty "こんにちは\n"
        `shouldBe` fields [aesonQQ|{"system": "こんにちは"}|]
    it "システムプロンプトの末尾の改行は1つだけ落とす" do
      mergeUi mempty mempty "こんにちは\n\n" `shouldBe` fields [aesonQQ|{"system": "こんにちは\n"}|]
    it "末尾に改行が無いシステムプロンプトはそのまま使う" do
      mergeUi mempty mempty "こんにちは" `shouldBe` fields [aesonQQ|{"system": "こんにちは"}|]
    it "途中の改行は保つ" do
      mergeUi mempty mempty "1行目\n2行目\n"
        `shouldBe` fields [aesonQQ|{"system": "1行目\n2行目"}|]
