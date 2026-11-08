-- | `extract`と`embed`のテスト。
--
-- 位置の計算は`Spec.Gguf.LocateSpec`が固定しているので、
-- ここでは実際のファイルに対して読み書きした結果を見る。
-- 特に書き戻した後にテンプレート以外の全てのバイトが元のままであることと、
-- 長さを揃えられない時にGGUFへ一切触れないことを確かめる。
module Spec.CommandSpec (tests) where

import Data.ByteString qualified as B
import Fixture
import Himari
import PatchGgufChatTemplate.Command (embed, extract)
import PatchGgufChatTemplate.Gguf.Locate (Span (..))
import PatchGgufChatTemplate.Pad (PadFailure (..))
import Test.Sandwich

-- | 組み立てたGGUFの中でテンプレートが占める位置。
spanOf :: ByteString -> ByteString -> Span
spanOf template content =
  Span{offset = toInteger (B.length prefix), size = B.length template}
 where
  (prefix, _) = B.breakSubstring template content

tests :: TopSpec
tests = do
  describe "extract" do
    it "可変長の値を挟んでもテンプレートをそのまま取り出し、位置を返す" do
      let template = "{{- 'hello' }}"
          content = buildGguf (Just template)
      withGgufFile content \ggufPath templatePath -> do
        extract ggufPath templatePath >>= (`shouldBe` spanOf template content)
        liftIO (B.readFile templatePath) >>= (`shouldBe` template)
  describe "embed" do
    it "書き戻してもテンプレート以外のバイトは1つも変えず、位置を返す" do
      let template = "{{- raise_exception('nope') }}"
          original = buildGguf (Just template)
          (prefix, rest) = B.breakSubstring template original
          suffix = B.drop (B.length template) rest
      withGgufFile original \ggufPath templatePath -> do
        writeBinaryFile templatePath "{{- 'ok' }}"
        embed ggufPath templatePath >>= (`shouldBe` spanOf template original)
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
    -- 長さを揃えられない理由は2つあり、どちらでも書き込む前に止まることを固定する。
    -- 埋め方の計算と書き込みの順番が入れ替わると、片方だけでは気付けない。
    for_
      [ ("伸びる置換は埋めようがない", (<> "!"), TemplateTooLong 1)
      , ("コメントに満たない端数は埋められない", B.dropEnd 2, PaddingTooSmall 2)
      ]
      \(caseName, patched, failure) ->
        it (caseName <> "ので書き込まずに止まる") do
          let template = "{{- 'short' }}"
              original = buildGguf (Just template)
          withGgufFile original \ggufPath templatePath -> do
            writeBinaryFile templatePath (patched template)
            embed ggufPath templatePath `shouldThrow` (== failure)
            liftIO (B.readFile ggufPath) >>= (`shouldBe` original)
