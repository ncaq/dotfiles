# 宣言された全ワークフローの構造とレイアウトを評価時に検証する。
#
# 存在しないノードへのリンクやノードの重なりはUIで開くまで気付きにくく、
# ノードを追加するたびに手動検証が漏れて何度も再発したため、
# NixOSのassertionsで機械的に検出する。
# `local.comfyui.workflows`を横断して検証するので、
# ワークフローを追加するだけで自動的に検証対象になる。
{ config, lib, ... }:
let
  link = import ./lib/link.nix { inherit lib; };
  linkTest = import ./lib/link-test.nix { inherit lib; };
  overlap = import ./lib/overlap.nix { inherit lib; };
  overlapTest = import ./lib/overlap-test.nix { inherit lib; };
  describeOverlap =
    pair: "  ${toString pair.a.id}(${pair.a.label}) と ${toString pair.b.id}(${pair.b.label})";
in
assert linkTest;
assert overlapTest;
{
  config.assertions = lib.concatLists (
    lib.mapAttrsToList (
      name: workflow:
      let
        linkErrors = link.invalidReferences workflow;
        overlappingNodePairs = overlap.overlappingNodePairs workflow.nodes;
      in
      [
        {
          assertion = linkErrors == [ ];
          message = ''
            ComfyUIワークフロー${name}で以下のリンク参照が不整合です:
            ${lib.concatStringsSep "\n" linkErrors}
          '';
        }
        {
          assertion = overlappingNodePairs == [ ];
          message = ''
            ComfyUIワークフロー${name}で以下のノードが重なっています(余白${toString overlap.margin}px未満を含む):
            ${lib.concatMapStringsSep "\n" describeOverlap overlappingNodePairs}
          '';
        }
      ]
    ) config.local.comfyui.workflows
  );
}
