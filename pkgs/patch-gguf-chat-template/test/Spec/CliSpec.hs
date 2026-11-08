-- | 引数の解釈と終了コードのテスト。
--
-- `lib/patch-gguf-chat-template.nix`はビルドした実行ファイルを引数付きで呼ぶ。
-- 引数の振り分けと、失敗が0以外の終了コードになることをここで固定する。
module Spec.CliSpec (tests) where

import Data.ByteString qualified as B
import Fixture
import Himari
import PatchGgufChatTemplate.Cli (Command (..), parseArgs, run)
import PatchGgufChatTemplate.Gguf.Locate (Span (..))
import Test.Sandwich

template :: ByteString
template = "{{- 'ok' }}"

tests :: TopSpec
tests = do
  describe "parseArgs" do
    it "extractを解釈する" do
      parseArgs ["extract", "model.gguf", "chat_template.jinja"]
        `shouldBe` Just (Extract "model.gguf" "chat_template.jinja")
    it "embedを解釈する" do
      parseArgs ["embed", "model.gguf", "chat_template.jinja"]
        `shouldBe` Just (Embed "model.gguf" "chat_template.jinja")
    for_
      [ ("引数が無い", [])
      , ("パスが足りない", ["extract", "model.gguf"])
      , ("引数が多い", ["extract", "model.gguf", "chat_template.jinja", "extra"])
      , ("知らないサブコマンド", ["patch", "model.gguf", "chat_template.jinja"])
      ]
      \(caseName, args) ->
        it (caseName <> "と解釈できない") do
          parseArgs args `shouldBe` Nothing
  describe "run" do
    it "extractを振り分けて位置を返す" do
      let content = buildGguf (Just template)
          (prefix, _) = B.breakSubstring template content
      withGgufFile content \ggufPath templatePath -> do
        run ["extract", ggufPath, templatePath]
          >>= (`shouldBe` Span{offset = toInteger (B.length prefix), size = B.length template})
        liftIO (B.readFile templatePath) >>= (`shouldBe` template)
    it "embedを振り分けて書き戻す" do
      withGgufFile (buildGguf (Just template)) \ggufPath templatePath -> do
        -- 11バイトの枠へ7バイトを書くので、残り4バイトが空のコメントで埋まる。
        writeBinaryFile templatePath "{{ 1 }}"
        void (run ["embed", ggufPath, templatePath])
        void (run ["extract", ggufPath, templatePath])
        liftIO (B.readFile templatePath) >>= (`shouldBe` "{{ 1 }}{##}")
    it "引数の形が違えば終了コード1で終わる" do
      run ["extract"] `shouldThrow` (== ExitFailure 1)
    it "GGUFを読めない失敗は終了コード1になる" do
      withGgufFile ("NOTGGUF" <> buildGguf (Just template)) \ggufPath templatePath ->
        run ["extract", ggufPath, templatePath] `shouldThrow` (== ExitFailure 1)
    it "長さを揃えられない失敗は終了コード1になる" do
      withGgufFile (buildGguf (Just template)) \ggufPath templatePath -> do
        writeBinaryFile templatePath (template <> "!")
        run ["embed", ggufPath, templatePath] `shouldThrow` (== ExitFailure 1)
