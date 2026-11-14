-- | 設定の読み方のテスト。
--
-- 秒数と接続先の環境変数を起動時に厳しく検査する振る舞いを、境界値で固定する。
module Spec.ConfigSpec (tests) where

import Himari
import IdleFreeMemory.Config (parseSeconds, validAuthority)
import Test.Sandwich

cases :: [(String, Maybe Int)]
cases =
  [ ("300", Just 300)
  , ("1", Just 1)
  , -- 0秒の待ちは待たずに回り続ける。
    ("0", Nothing)
  , ("-1", Nothing)
  , ("1.5", Nothing)
  , ("1e3", Nothing)
  , ("", Nothing)
  , -- `Read`は前後の空白を読み飛ばすが、書き損じなので通さない。
    ("60 ", Nothing)
  , (" 60", Nothing)
  , ("+60", Nothing)
  , -- 先頭のゼロは数字だけの文字列なので、そのまま10進数として読む。
    ("060", Just 60)
  , -- マイクロ秒にして`Int`へ収まる最大の値。
    ("9223372036854", Just 9223372036854)
  , -- マイクロ秒にすると`Int`へ収まらない。
    ("9223372036855", Nothing)
  , -- `Int`として読むと桁あふれで正の値に化ける。
    ("18446744073709551917", Nothing)
  ]

authorities :: [(Text, Bool)]
authorities =
  [ -- ホストの書き方はIPv6とIPv4と名前のどれも受け付ける。
    ("[::1]:8188", True)
  , ("127.0.0.1:8188", True)
  , ("localhost:8188", True)
  , -- ポートを省くとHTTPの既定の80になる。
    ("[::1]", True)
  , -- `parseRequest`はホストが空でも通すので、こちらで弾く。
    ("", False)
  , (":8188", False)
  , ("[::1]:99999", False)
  , ("[::1]:x", False)
  , -- スキームはこちらが足すので、付けて渡すと二重になる。
    ("http://[::1]:8188", False)
  ]

tests :: TopSpec
tests = do
  describe "parseSeconds" do
    for_ cases \(raw, expected) ->
      it (show raw <> " -> " <> show expected) do
        parseSeconds raw `shouldBe` expected
  describe "validAuthority" do
    for_ authorities \(authority, expected) ->
      it (show authority <> " -> " <> show expected) do
        validAuthority authority `shouldBe` expected
