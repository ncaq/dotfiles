-- | フラグ名の決め方のテスト。
--
-- 名前の決め方は実機で確かめにくい。
-- `--help`を見れば分かるが、
-- どういう時にウィジェット名から離れるのかは、
-- ワークフローを1つ見ても読み取れない。
module Spec.NameSpec (tests) where

import ComfyWorkflow.Name
import Himari
import Test.Sandwich

tests :: TopSpec
tests = describe "Name" do
  describe "slug" do
    it "ASCIIの単語だけを残す" do
      slug "Positive Prompt" `shouldBe` "positive-prompt"
      slug "unet_name" `shouldBe` "unet-name"
    it "日本語のタイトルからは名前を作れない" do
      slug "生成寸法" `shouldBe` ""
    it "英字で始まらないものは作れなかったものとして扱う" do
      -- `参考画像2`のようなタイトルからは数字しか残らない。
      -- `--2`は負の数と区別が付かない。
      slug "参考画像2" `shouldBe` ""
  describe "candidates" do
    it "ウィジェット名、タイトル、その組み合わせ、ノードIDの順に並べる" do
      candidates "4" "Positive Prompt" "text"
        `shouldBe` ["text", "positive-prompt", "positive-prompt-text", "node4-text"]
    it "タイトルから名前を作れなければその候補を落とす" do
      candidates "4" "生成内容" "text" `shouldBe` ["text", "node4-text"]
  describe "resolveNames" do
    it "衝突しない名前はそのまま" do
      resolveNames [] [["seed"], ["steps"]] `shouldBe` ["seed", "steps"]
    it "衝突した組だけが次の候補へ降りる" do
      resolveNames [] [["text", "positive"], ["text", "negative"], ["cfg"]]
        `shouldBe` ["positive", "negative", "cfg"]
    it "全体のオプションが先に取っている名前には譲る" do
      resolveNames ["seed"] [["seed", "sampler-seed"]] `shouldBe` ["sampler-seed"]
    it "候補を使い切っても名前を重複させない" do
      case resolveNames [] [["a"], ["a"]] of
        [first', second'] -> first' `shouldNotBe` second'
        other -> expectationFailure ("2つの名前が返っていません: " <> show other)
