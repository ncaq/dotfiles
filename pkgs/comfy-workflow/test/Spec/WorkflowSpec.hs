-- | UI形式のJSONからワークフローを読む経路のテスト。
--
-- ここが壊れても例外にはならず、
-- 「フラグが出ない」「seedが配られない」という形で現れる。
module Spec.WorkflowSpec (tests) where

import ComfyWorkflow.Workflow
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "Workflow" do
  describe "parseWorkflow" do
    it "数値のノードIDを文字列にして、タイトルと値の並びを読む" do
      let workflow =
            parseWorkflow
              [aesonQQ|{
                "nodes": [
                  {
                    "id": 2,
                    "type": "CLIPTextEncode",
                    "title": "Positive Prompt",
                    "widgets_values": ["1girl"]
                  },
                  {"id": 5, "type": "KSampler", "widgets_values": [0, "randomize", 28]}
                ],
                "links": []
              }|]
      fmap (.nodes) workflow
        `shouldBe` Right
          [ Node
              { nodeId = "2"
              , nodeType = "CLIPTextEncode"
              , title = Just "Positive Prompt"
              , widgetsValues = [String "1girl"]
              }
          , Node
              { nodeId = "5"
              , nodeType = "KSampler"
              , title = Nothing
              , widgetsValues = [Number 0, String "randomize", Number 28]
              }
          ]
    it "App Modeの入力を2要素の形と説明付きの3要素の形で読む" do
      let workflow =
            parseWorkflow
              [aesonQQ|{
                "nodes": [],
                "extra": {
                  "linearData": {
                    "inputs": [
                      [2, "text", {"description": "生成する画像の内容", "height": 160}],
                      [5, "seed"]
                    ]
                  }
                }
              }|]
      fmap (.appInputs) workflow
        `shouldBe` Right
          [ AppInput{nodeId = "2", widget = "text", description = Just "生成する画像の内容"}
          , AppInput{nodeId = "5", widget = "seed", description = Nothing}
          ]
    it "App Modeの定義が無ければ入力は空" do
      fmap (.appInputs) (parseWorkflow [aesonQQ|{"nodes": []}|]) `shouldBe` Right []
    it "widgets_valuesが無いノードや辞書で書かれたノードは値の並びが空" do
      let workflow =
            parseWorkflow
              [aesonQQ|{
                "nodes": [
                  {"id": 6, "type": "VAEDecode"},
                  {"id": 7, "type": "Something", "widgets_values": {"value": 1}}
                ]
              }|]
      fmap (fmap (.widgetsValues) . (.nodes)) workflow `shouldBe` Right [[], []]
    it "整数でないノードIDは読めない" do
      isLeft (parseWorkflow [aesonQQ|{"nodes": [{"id": 1.5, "type": "X"}]}|]) `shouldBe` True
    it "文字列のノードIDはそのまま使う" do
      let workflow = parseWorkflow [aesonQQ|{"nodes": [{"id": "16:3", "type": "X"}]}|]
      fmap (fmap (.nodeId) . (.nodes)) workflow `shouldBe` Right ["16:3"]
    it "ノードIDとウィジェット名の揃っていないApp Mode入力は読めない" do
      let workflow =
            parseWorkflow [aesonQQ|{"nodes": [], "extra": {"linearData": {"inputs": [[2]]}}}|]
      isLeft workflow `shouldBe` True
