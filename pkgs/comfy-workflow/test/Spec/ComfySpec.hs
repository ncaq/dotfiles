-- | 接続先の`host:port`の読み方のテスト。
--
-- 接続先はIPv6のアドレスを角括弧で囲んで書く。
-- 最後の`:`で分けるので角括弧の中の`:`は分けずに済むが、
-- ポートを省いた`[::1]`のような書き方は、
-- 分けた後の`1]`がポートとして読めないことで弾いている。
-- 実装を変えた時にそれが崩れても、使う側は接続に失敗するまで気付けない。
module Spec.ComfySpec (tests) where

import ComfyWorkflow.Comfy (Target (..), authorityOf, parseAuthority)
import Himari
import Test.Sandwich

-- | 読めるべき接続先と、読んだ結果。
valid :: [(Text, Target)]
valid =
  [ -- ホストの書き方はIPv6とIPv4と名前のどれも受け付ける。
    ("[::1]:8188", Target{host = "[::1]", port = 8188})
  , ("127.0.0.1:8188", Target{host = "127.0.0.1", port = 8188})
  , ("localhost:8188", Target{host = "localhost", port = 8188})
  ]

-- | 読めないべき接続先。
invalid :: [Text]
invalid =
  [ -- ポートを省いた書き方。
    "[::1]"
  , "localhost"
  , -- ホストの無い書き方。
    ":8188"
  , -- 数字でないポート。
    "[::1]:x"
  ]

tests :: TopSpec
tests = describe "Comfy" do
  describe "parseAuthority" do
    for_ valid \(authority, target) ->
      it (convert authority <> "を読む") do
        parseAuthority authority `shouldBe` Right target
    for_ invalid \authority ->
      it (convert authority <> "を読まない") do
        isLeft (parseAuthority authority) `shouldBe` True
  describe "authorityOf" do
    for_ valid \(authority, target) ->
      it (convert authority <> "へ戻す") do
        authorityOf target `shouldBe` authority
