-- | 振り直すseedの見つけ方のテスト。
module Spec.SeedSpec (tests) where

import ComfyWorkflow.Seed
import ComfyWorkflow.Slot (Slot (..), WidgetType (..))
import ComfyWorkflow.Workflow (Node (..))
import Himari
import Test.Sandwich

slot :: Text -> Text -> WidgetType -> Slot
slot nodeId name widgetType =
  Slot
    { address = nodeId <> "." <> name
    , name
    , instanceId = nodeId
    , nodeType = "KSampler"
    , widgetType
    , currentValue = Null
    }

sampler :: Text -> Text -> Node
sampler nodeId control =
  Node
    { nodeId
    , nodeType = "KSampler"
    , title = Nothing
    , widgetsValues =
        [Number 0, String control, Number 28, Number 5.5, String "euler", String "normal", Number 1]
    }

samplerSlots :: Text -> [Slot]
samplerSlots nodeId =
  [ slot nodeId "seed" IntWidget
  , slot nodeId "steps" IntWidget
  , slot nodeId "cfg" FloatWidget
  , slot nodeId "sampler_name" (ComboWidget [])
  , slot nodeId "scheduler" (ComboWidget [])
  , slot nodeId "denoise" FloatWidget
  ]

tests :: TopSpec
tests = describe "Seed" do
  it "randomizeのseedを全て拾う" do
    -- `anima-standard`はサンプラーが3つあり、揃って動く必要がある。
    let nodes = [sampler "7" "randomize", sampler "14" "randomize", sampler "17" "randomize"]
        slots = concatMap samplerSlots ["7", "14", "17"]
    seedTargets nodes slots `shouldBe` ["7.seed", "14.seed", "17.seed"]
  it "fixedのseedには触らない" do
    -- UIで意図して固定したものが、APIから投げた時だけ動くのはおかしい。
    seedTargets [sampler "5" "fixed"] (samplerSlots "5") `shouldBe` []
  it "incrementやdecrementも振り直す" do
    seedTargets [sampler "5" "increment"] (samplerSlots "5") `shouldBe` ["5.seed"]
  it "seedの前に別のウィジェットがあっても拾う" do
    -- FaceDetailerはseedの前にguide_sizeなどが並ぶ。
    let node =
          Node
            { nodeId = "14"
            , nodeType = "FaceDetailer"
            , title = Nothing
            , widgetsValues =
                [Number 512, Bool True, Number 1024, Number 0, String "randomize", Number 14]
            }
        slots =
          [ slot "14" "guide_size" FloatWidget
          , slot "14" "guide_size_for" BooleanWidget
          , slot "14" "max_size" FloatWidget
          , slot "14" "seed" IntWidget
          , slot "14" "steps" IntWidget
          ]
    seedTargets [node] slots `shouldBe` ["14.seed"]
  it "振る舞いの名前が無いseedは振り直さない" do
    let node =
          Node
            { nodeId = "5"
            , nodeType = "KSampler"
            , title = Nothing
            , widgetsValues = [Number 0, Number 28]
            }
    seedTargets [node] (samplerSlots "5") `shouldBe` []
  it "noise_seedも対象にする" do
    let node =
          Node
            { nodeId = "9"
            , nodeType = "KSamplerAdvanced"
            , title = Nothing
            , widgetsValues = [String "enable", Number 0, String "randomize", Number 20]
            }
        slots =
          [ slot "9" "add_noise" (ComboWidget [])
          , slot "9" "noise_seed" IntWidget
          , slot "9" "steps" IntWidget
          ]
    seedTargets [node] slots `shouldBe` ["9.noise_seed"]
  it "振る舞いの名前と同じ文字列を持つCOMBOの値は数値の後にしか見ない" do
    -- `fixed`という選択肢を持つCOMBOの値を、seedの振る舞いと取り違えない。
    let node =
          Node
            { nodeId = "3"
            , nodeType = "Something"
            , title = Nothing
            , widgetsValues = [String "fixed", String "randomize"]
            }
    seedTargets [node] [slot "3" "seed" IntWidget] `shouldBe` []
  it "controlWordsはフロントエンドの4つ" do
    controlWords `shouldBe` ["fixed", "increment", "decrement", "randomize"]
