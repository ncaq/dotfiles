-- | 公式CLIの`--json`の出力との契約のテスト。
--
-- `comfy workflow slots`のキー名と`type`から`WidgetType`への対応、
-- そして封筒の形は全てこのモジュールの`FromJSON`にある。
-- 公式CLIは更新が速く、封筒の形式も若いAPIなので、
-- 実機の出力を写して固定しておく。
module Spec.SlotSpec (tests) where

import ComfyWorkflow.Slot
import Himari
import Test.Sandwich

-- | comfy-cli 1.25.0の`comfy --json workflow slots`から写した1件。
sampledSlot :: Value
sampledSlot =
  [aesonQQ|{
    "address": "5.sampler_name",
    "name": "sampler_name",
    "type": "COMBO",
    "current_value": "euler_ancestral",
    "instance_id": "5",
    "node_type": "KSampler",
    "enum": ["euler", "euler_ancestral", "dpmpp_2m"]
  }|]

-- | `fromJSON`の`Result`はsandwichの`Success`と名前が被るので、
-- 一度JSONの文字列に戻して`Either`で受ける。
decode :: (FromJSON a) => Value -> Either String a
decode = eitherDecode . encode

tests :: TopSpec
tests = describe "Slot" do
  describe "FromJSON Slot" do
    it "実機の出力の1件を読む" do
      decode sampledSlot
        `shouldBe` Right
          Slot
            { address = "5.sampler_name"
            , name = "sampler_name"
            , instanceId = "5"
            , nodeType = "KSampler"
            , widgetType = ComboWidget ["euler", "euler_ancestral", "dpmpp_2m"]
            , currentValue = String "euler_ancestral"
            }
    it "typeをウィジェットの型へ対応させる" do
      -- `aesonQQ`は値の差し込みに対応していないので、`Map`で組む。
      let slotWith :: Text -> Map Text Value
          slotWith kind =
            mempty
              & at "address" ?~ "1.x"
              & at "name" ?~ "x"
              & at "type" ?~ String kind
              & at "instance_id" ?~ "1"
              & at "node_type" ?~ "N"
          typed :: Text -> Either String WidgetType
          typed kind = (\(slot :: Slot) -> slot.widgetType) <$> decode (toJSON (slotWith kind))
      typed "INT" `shouldBe` Right IntWidget
      typed "FLOAT" `shouldBe` Right FloatWidget
      typed "BOOLEAN" `shouldBe` Right BooleanWidget
      typed "STRING" `shouldBe` Right StringWidget
      typed "COMBO" `shouldBe` Right (ComboWidget [])
      typed "IMAGEUPLOAD" `shouldBe` Right (OtherWidget "IMAGEUPLOAD")
    it "enumとcurrent_valueは無くても読める" do
      let slot :: Either String Slot
          slot =
            decode
              [aesonQQ|{
                "address": "2.text", "name": "text", "type": "STRING",
                "instance_id": "2", "node_type": "CLIPTextEncode"
              }|]
      fmap (.currentValue) slot `shouldBe` Right Null
  describe "FromJSON Envelope" do
    it "成功の封筒からdataを取り出す" do
      let envelope :: Either String (Envelope Slots)
          envelope =
            decode
              [aesonQQ|{
                "schema": "envelope/1", "type": "envelope", "ok": true,
                "command": "workflow slots", "version": "1.25.0", "where": "local",
                "data": {
                  "workflow": "x.json", "id": "x", "count": 1,
                  "slots": [{
                    "address": "5.seed", "name": "seed", "type": "INT", "current_value": 0,
                    "instance_id": "5", "node_type": "KSampler"
                  }]
                },
                "error": null
              }|]
      fmap (\e -> (e.ok, fmap (\(Slots slots) -> length slots) e.payload)) envelope
        `shouldBe` Right (True, Just 1)
    it "失敗の封筒からerrorを取り出す" do
      let envelope :: Either String (Envelope Slots)
          envelope =
            decode
              [aesonQQ|{
                "schema": "envelope/1", "type": "envelope", "ok": false,
                "command": "workflow slots", "version": "1.25.0", "where": null,
                "data": null,
                "error": {
                  "code": "cql_no_graph",
                  "message": "cannot reach http://127.0.0.1:9/object_info",
                  "hint": "run `comfy launch` first"
                }
              }|]
      fmap (\e -> (e.ok, e.payload, e.failure)) envelope
        `shouldBe` Right
          ( False
          , Nothing
          , Just
              ComfyError
                { code = "cql_no_graph"
                , message = "cannot reach http://127.0.0.1:9/object_info"
                , hint = Just "run `comfy launch` first"
                }
          )
    it "dataの無い成功も読める" do
      let envelope :: Either String (Envelope Slots)
          envelope = decode [aesonQQ|{"ok": true}|]
      fmap (\e -> (e.ok, e.payload, e.failure)) envelope `shouldBe` Right (True, Nothing, Nothing)
  describe "describeError" do
    it "メッセージとコードとヒントを並べる" do
      describeError ComfyError{code = "c", message = "m", hint = Just "h"} `shouldBe` "m (c)\nh"
      describeError ComfyError{code = "c", message = "m", hint = Nothing} `shouldBe` "m (c)"
