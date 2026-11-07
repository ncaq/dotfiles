-- | API形式の手直しと、履歴からの結果の読み取りのテスト。
--
-- どちらも間違えても例外にならず、
-- 投げる内容や表示されるパスが違うだけの壊れ方をする。
module Spec.PromptSpec (tests) where

import ComfyWorkflow.Prompt
import ComfyWorkflow.Workflow (Node (..))
import Himari
import Test.Sandwich

loraLoader :: Node
loraLoader =
  Node
    { nodeId = "16"
    , nodeType = "Lora Loader (LoraManager)"
    , title = Nothing
    , widgetsValues = [[aesonQQ|{"textWidgetName": "text"}|], String "<lora:a:0.8>", Array mempty]
    }

-- | API形式のプロンプト全体を`Value`のまま手直しする。
-- テストではJSONのQuasiQuoteで書いた`Value`同士を比べたい。
fixup :: Value -> Value
fixup value = maybe value (toJSON . fixupPrompt [loraLoader]) (asObject value)

tests :: TopSpec
tests = describe "Prompt" do
  describe "fixupPrompt" do
    it "LoraManagerのtextを拡張が描く位置から埋める" do
      fixup
        [aesonQQ|{
          "16": {
            "class_type": "Lora Loader (LoraManager)",
            "inputs": {"model": ["1", 0], "➕ Add Lora": ""}
          }
        }|]
        `shouldBe` [aesonQQ|{
          "16": {
            "class_type": "Lora Loader (LoraManager)",
            "inputs": {"model": ["1", 0], "text": "<lora:a:0.8>"}
          }
        }|]
    it "既にtextがあれば触らない" do
      -- 公式の変換が対応した時に、ここが何もしなくなるため。
      let prompt = [aesonQQ|{"16": {"inputs": {"text": "already"}}}|]
      fixup prompt `shouldBe` prompt
    it "対象でないノードは触らない" do
      let prompt = [aesonQQ|{"5": {"class_type": "KSampler", "inputs": {"seed": 1}}}|]
      fixup prompt `shouldBe` prompt
  describe "applySeed" do
    it "指定したノードの入力へseedを書き、他には触らない" do
      let prompt =
            [aesonQQ|{
              "5": {"class_type": "KSampler", "inputs": {"seed": 0, "steps": 28}},
              "11": {"class_type": "KSampler", "inputs": {"seed": 0}},
              "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0]}}
            }|]
          targets = [("5", "seed"), ("11", "seed")]
          seeded = maybe prompt (toJSON . applySeed 314 targets) (asObject prompt)
      seeded
        `shouldBe` [aesonQQ|{
          "5": {"class_type": "KSampler", "inputs": {"seed": 314, "steps": 28}},
          "11": {"class_type": "KSampler", "inputs": {"seed": 314}},
          "6": {"class_type": "VAEDecode", "inputs": {"samples": ["5", 0]}}
        }|]
    it "存在しないノードを指しても壊れない" do
      let prompt = [aesonQQ|{"5": {"inputs": {"seed": 0}}}|]
          seeded = maybe prompt (toJSON . applySeed 1 [("9", "seed")]) (asObject prompt)
      seeded `shouldBe` prompt
  describe "readHistory" do
    it "保存されたファイルを集める" do
      let history =
            [aesonQQ|{
              "abc": {
                "status": {"status_str": "success"},
                "outputs": {
                  "15": {"images": [{"filename": "a.png", "subfolder": "sub", "type": "output"}]}
                }
              }
            }|]
      readHistory "abc" history `shouldBe` Right (Succeeded ["sub/a.png"])
    it "サブフォルダが無ければそのままの名前" do
      let history =
            [aesonQQ|{
              "abc": {
                "outputs": {
                  "15": {"gifs": [{"filename": "a.mp4", "subfolder": "", "type": "output"}]}
                }
              }
            }|]
      readHistory "abc" history `shouldBe` Right (Succeeded ["a.mp4"])
    it "一時ファイルは拾わない" do
      let history =
            [aesonQQ|{
              "abc": {
                "outputs": {
                  "15": {"images": [{"filename": "a.png", "subfolder": "", "type": "temp"}]}
                }
              }
            }|]
      readHistory "abc" history `shouldBe` Right (Succeeded [])
    it "失敗した履歴はメッセージ付きで報告する" do
      let history =
            [aesonQQ|{
              "abc": {
                "status": {"status_str": "error", "messages": ["boom", "日本語"]},
                "outputs": {}
              }
            }|]
      case readHistory "abc" history of
        Right (Failed reason) -> do
          reason `textShouldContain` "error"
          -- どのノードで何が起きたのかは`messages`にしか無い。
          reason `textShouldContain` "boom"
          -- 非ASCIIをエスケープせずそのまま見せる。
          reason `textShouldContain` "日本語"
        other -> expectationFailure ("失敗として報告されていません: " <> show other)
    it "statusの無い履歴は失敗にしない" do
      -- 上流が形を変えた時に、成功した生成が失敗するようになる方が困る。
      readHistory "abc" [aesonQQ|{"abc": {"outputs": {}}}|] `shouldBe` Right (Succeeded [])
    it "履歴に無いprompt_idはエラー" do
      isLeft (readHistory "zzz" [aesonQQ|{}|]) `shouldBe` True
  describe "jsonText" do
    it "文字列を引用符付きで、非ASCIIをエスケープせずに出す" do
      jsonText (String "日本語 \"q\"") `shouldBe` "\"日本語 \\\"q\\\"\""
  describe "relativeOutput" do
    it "絶対パスを弾く" do
      isLeft (relativeOutput "" "/etc/passwd") `shouldBe` True
    it "親ディレクトリへの脱出を弾く" do
      isLeft (relativeOutput ".." "a.png") `shouldBe` True
      isLeft (relativeOutput "sub" "../a.png") `shouldBe` True
    it "名前の一部の..は許す" do
      relativeOutput "" "a..b.png" `shouldBe` Right "a..b.png"
