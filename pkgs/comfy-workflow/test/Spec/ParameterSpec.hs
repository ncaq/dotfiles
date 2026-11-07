-- | App Modeの入力定義からパラメータを決める部分と、値の解釈のテスト。
module Spec.ParameterSpec (tests) where

import ComfyWorkflow.Parameter
import ComfyWorkflow.Slot (Slot (..), WidgetType (..))
import ComfyWorkflow.Workflow (AppInput (..), Node (..), Workflow (..))
import Himari
import Test.Sandwich

textSlot :: Text -> Slot
textSlot nodeId =
  Slot
    { address = nodeId <> ".text"
    , name = "text"
    , instanceId = nodeId
    , nodeType = "CLIPTextEncode"
    , widgetType = StringWidget
    , currentValue = String "既定"
    }

seedSlot :: Text -> Slot
seedSlot nodeId =
  Slot
    { address = nodeId <> ".seed"
    , name = "seed"
    , instanceId = nodeId
    , nodeType = "KSampler"
    , widgetType = IntWidget
    , currentValue = Number 0
    }

textNode :: Text -> Maybe Text -> Node
textNode nodeId title =
  Node{nodeId, nodeType = "CLIPTextEncode", title, widgetsValues = [String "既定"]}

workflow :: [Node] -> [AppInput] -> Workflow
workflow nodes appInputs = Workflow{nodes, appInputs}

input :: Text -> Text -> AppInput
input nodeId widget = AppInput{nodeId, widget, description = Nothing}

flagsOf :: Either Text [Parameter] -> Either Text [Text]
flagsOf = fmap (fmap (.flag))

tests :: TopSpec
tests = describe "Parameter" do
  describe "parameters" do
    it "ウィジェット名がそのままフラグになる" do
      let params = parameters (workflow [textNode "4" Nothing] [input "4" "text"]) [textSlot "4"]
      flagsOf params `shouldBe` Right ["text"]
    it "衝突したウィジェットはノードのタイトルを使う" do
      -- `anima-standard`のポジティブとネガティブがこの形になる。
      let params =
            parameters
              ( workflow
                  [textNode "4" (Just "Positive Prompt"), textNode "5" (Just "Negative Prompt")]
                  [input "4" "text", input "5" "text"]
              )
              [textSlot "4", textSlot "5"]
      flagsOf params `shouldBe` Right ["positive-prompt", "negative-prompt"]
    it "使えるタイトルが無ければノードIDを使う" do
      let params =
            parameters
              ( workflow
                  [textNode "4" (Just "生成内容"), textNode "5" (Just "除外")]
                  [input "4" "text", input "5" "text"]
              )
              [textSlot "4", textSlot "5"]
      flagsOf params `shouldBe` Right ["node4-text", "node5-text"]
    it "seedはパラメータにしない" do
      -- 全体の`--seed`が全てのサンプラーへ配るので、1つのノードを指すフラグは持たない。
      let sampler = Node{nodeId = "7", nodeType = "KSampler", title = Nothing, widgetsValues = []}
          params = parameters (workflow [sampler] [input "7" "seed"]) [seedSlot "7"]
      flagsOf params `shouldBe` Right []
    it "説明はApp Modeの入力定義から取る" do
      let described = AppInput{nodeId = "4", widget = "text", description = Just "生成する画像の内容"}
          params = parameters (workflow [textNode "4" Nothing] [described]) [textSlot "4"]
      fmap (fmap (.description)) params `shouldBe` Right [Just "生成する画像の内容"]
    it "存在しないノードを指す入力はエラー" do
      let params = parameters (workflow [textNode "4" Nothing] [input "9" "text"]) [textSlot "4"]
      isLeft params `shouldBe` True
    it "存在しないウィジェットを指す入力はエラー" do
      let params =
            parameters (workflow [textNode "4" Nothing] [input "4" "nonexistent"]) [textSlot "4"]
      isLeft params `shouldBe` True
  describe "parseValue" do
    it "整数を読む" do
      parseValue IntWidget "28" `shouldBe` Right (Number 28)
      isLeft (parseValue IntWidget "28.5") `shouldBe` True
    it "小数を読む" do
      parseValue FloatWidget "5.5" `shouldBe` Right (Number 5.5)
    it "真偽値の言い回しを受け付ける" do
      for_ ["true", "1", "yes", "on", "TRUE"] \text ->
        parseValue BooleanWidget text `shouldBe` Right (Bool True)
      for_ ["false", "0", "no", "off"] \text ->
        parseValue BooleanWidget text `shouldBe` Right (Bool False)
      isLeft (parseValue BooleanWidget "maybe") `shouldBe` True
    it "選択肢にあるものだけを受け付ける" do
      parseValue (ComboWidget ["euler", "ddim"]) "ddim" `shouldBe` Right (String "ddim")
      isLeft (parseValue (ComboWidget ["euler", "ddim"]) "lcm") `shouldBe` True
    it "選択肢が無いCOMBOは素通しする" do
      parseValue (ComboWidget []) "anything" `shouldBe` Right (String "anything")
    it "文字列は素通しする" do
      parseValue StringWidget "123" `shouldBe` Right (String "123")
  describe "positiveInt" do
    it "1以上を受け付ける" do
      positiveInt "1" `shouldBe` Right 1
    it "0以下を弾く" do
      -- 0以下を通すと何も投げずに正常終了してしまう。
      isLeft (positiveInt "0") `shouldBe` True
      isLeft (positiveInt "-3") `shouldBe` True
    it "数でないものを弾く" do
      isLeft (positiveInt "many") `shouldBe` True
