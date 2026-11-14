# `lib/ollama-context.nix`の配分が、
# 説明に書いた前提を満たし続けることを確かめる。
#
# ハーネスへ伝える圧縮の閾値と応答の上限は、
# 足してcontextに収まらないと長い会話で長い応答を生成した瞬間に溢れる。
# また比率の1/4は、
# CUDAのホストで応答の上限がClaude Codeの既定の32000を下回らないことを根拠に選んでいる。
# 長さを変えた時にどちらかが崩れても、
# 評価は黙って通ってしまう。
{ lib }:
let
  ollamaContext = import ../../lib/ollama-context.nix;
  inherit (ollamaContext) budget;
  lengths = lib.attrValues ollamaContext.length ++ [ ollamaContext.translateLength ];
in
assert lib.all (
  length:
  let
    b = budget length;
  in
  lib.assertMsg (
    b.context == length && b.output + b.history == b.context
  ) "長さ${toString length}の配分の合計がcontextと一致しません"
) lengths;
assert lib.assertMsg (
  (budget ollamaContext.length.cuda).output >= 32000
) "CUDAのホストの応答の上限がClaude Codeの既定の32000を下回っています";
true
