# `builder.mkNode`がオプション引数を省略した時の形状を検証する。
{ lib }:
let
  builder = import ../../../../nixos/host/bullet/comfyui/workflow/lib/builder.nix { inherit lib; };
  # オプション引数を全て省略した素のノード。
  plainNode = builder.mkNode {
    id = 1;
    type = "TestNode";
    pos = [
      0
      0
    ];
    size = [
      10
      10
    ];
    order = 0;
  };
in
# mkNodeのオプション属性は省略時に属性ごと付かない。
# nullのまま出力するとComfyUIのJSONとして意味が変わり得る。
assert lib.assertMsg (
  !(plainNode ? widgets_values) && !(plainNode ? title)
) "省略したオプション属性が素のノードに付いています";
assert lib.assertMsg (
  plainNode.properties."Node name for S&R" == "TestNode"
) "S&R用のノード型名が設定されていません";
true
