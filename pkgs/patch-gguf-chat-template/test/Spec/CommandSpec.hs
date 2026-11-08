-- | `extract`と`embed`のテスト。
--
-- 位置の計算は`Spec.GgufSpec`が固定しているので、
-- ここでは実際のファイルに対して読み書きした結果を見る。
-- 特に書き戻した後にテンプレート以外の全てのバイトが元のままであることを確かめる。
module Spec.CommandSpec (tests) where

import Data.ByteString qualified as B
import Fixture
import Himari
import PatchGgufChatTemplate.Command (embed, extract)
import PatchGgufChatTemplate.Pad (PadFailure (..))
import Test.Sandwich

tests :: TopSpec
tests = do
  describe "extract" do
    it "可変長の値を挟んでもテンプレートをそのまま取り出す" do
      let template = "{{- 'hello' }}"
      withGgufFile (buildGguf (Just template)) \ggufPath templatePath -> do
        void (extract ggufPath templatePath)
        liftIO (B.readFile templatePath) >>= (`shouldBe` template)
  describe "embed" do
    it "書き戻してもテンプレート以外のバイトは1つも変えない" do
      let template = "{{- raise_exception('nope') }}"
          original = buildGguf (Just template)
          (prefix, rest) = B.breakSubstring template original
          suffix = B.drop (B.length template) rest
      withGgufFile original \ggufPath templatePath -> do
        writeBinaryFile templatePath "{{- 'ok' }}"
        void (embed ggufPath templatePath)
        result <- liftIO (B.readFile ggufPath)
        B.length result `shouldBe` B.length original
        B.take (B.length prefix) result `shouldBe` prefix
        B.drop (B.length result - B.length suffix) result `shouldBe` suffix
    it "縮んだ分はJinjaのコメントで埋められ、取り出すと現れる" do
      let template = "{{- raise_exception('nope') }}"
      withGgufFile (buildGguf (Just template)) \ggufPath templatePath -> do
        writeBinaryFile templatePath "{{- 'ok' }}"
        void (embed ggufPath templatePath)
        void (extract ggufPath templatePath)
        -- 30バイトの枠へ11バイトを書き、残る19バイトのうち4バイトをコメントの記号が使う。
        liftIO (B.readFile templatePath)
          >>= (`shouldBe` ("{{- 'ok' }}{#" <> B.replicate 15 0x20 <> "#}"))
    it "伸びる置換は埋めようがないので書き込まずに止まる" do
      let template = "{{- 'short' }}"
          original = buildGguf (Just template)
      withGgufFile original \ggufPath templatePath -> do
        writeBinaryFile templatePath (template <> "!")
        embed ggufPath templatePath `shouldThrow` (== TemplateTooLong 1)
        liftIO (B.readFile ggufPath) >>= (`shouldBe` original)
