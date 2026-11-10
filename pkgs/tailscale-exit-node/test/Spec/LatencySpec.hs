-- | `tailscale ping`の出力の読み方のテスト。
module Spec.LatencySpec (tests) where

import Himari
import TailscaleExitNode.Latency (parsePingLatency)
import Test.Sandwich

cases :: [(String, Text, Maybe NominalDiffTime)]
cases =
  [ ("ミリ秒を読む", "pong from seminar (100.82.4.93) via 192.168.10.88:41641 in 4ms", Just 0.004)
  , ("0秒を読む", "pong from seminar (100.75.108.73) via [240b:11::143d]:41641 in 0s", Just 0)
  , ("DERP経由のミリ秒を読む", "pong from seminar (100.82.4.93) via DERP(tok) in 38ms", Just 0.038)
  , ("1秒以上の小数の秒を読む", "pong from seminar (100.82.4.93) via DERP(tok) in 1.234s", Just 1.234)
  , ("整数の秒を読む", "pong from seminar (100.82.4.93) via DERP(tok) in 2s", Just 2)
  , ("末尾の改行は無視する", "pong from seminar (100.82.4.93) via DERP(tok) in 38ms\n", Just 0.038)
  ,
    ( "複数行なら最後のpongを読む"
    , "pong from seminar (100.82.4.93) via DERP(tok) in 38ms\n"
        <> "pong from seminar (100.82.4.93) via 192.168.10.88:41641 in 4ms\n"
    , Just 0.004
    )
  ,
    ( -- `-c 1`でDERP経由のpongだけが返ると、直接の経路ができなかったことが標準エラー出力へ出る。
      -- 標準出力とまとめて受け取るので、pongの後ろに行が続く。
      "pongの後ろに直接の経路ができなかった行が続いても読む"
    , "pong from seminar (100.82.4.93) via DERP(tok) in 38ms\n"
        <> "direct connection not established\n"
    , Just 0.038
    )
  ,
    ( "pongの前に別の行があっても読む"
    , "2026/11/11 00:00:00 some warning in 5ms of something\n"
        <> "pong from seminar (100.82.4.93) via DERP(tok) in 38ms\n"
    , Just 0.038
    )
  , ("pongではない行のレイテンシらしい文字列は読まない", "connected in 4ms", Nothing)
  , ("届かなかった出力は読まない", "ping \"seminar\" timed out", Nothing)
  , ("ノードが見つからない出力は読まない", "no matching peer", Nothing)
  , ("知らない単位は読まない", "pong from seminar (100.82.4.93) via DERP(tok) in 4h", Nothing)
  , ("数字の無いものは読まない", "pong from seminar (100.82.4.93) via DERP(tok) in ms", Nothing)
  , ("空の出力は読まない", "", Nothing)
  ]

tests :: TopSpec
tests = describe "parsePingLatency" do
  for_ cases \(name, output, expected) ->
    it name do
      parsePingLatency output `shouldBe` expected
