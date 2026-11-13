# 正常なワークフローを拒否しないこと。
{ lib }:
let
  inherit (import ./fixture.nix { inherit lib; }) run allEmpty;
in
assert lib.assertMsg (allEmpty (run { })) "正常なワークフローを拒否しました";
true
