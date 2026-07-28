# 宣言された全ワークフローの構造とレイアウトを評価時に検証する。
#
# 存在しないノードへのリンクやノードの重なりはUIで開くまで気付きにくく、
# ノードを追加するたびに手動検証が漏れて何度も再発したため、
# NixOSのassertionsで機械的に検出する。
# `local.comfyui.workflows`を横断して検証するので、
# ワークフローを追加するだけで自動的に検証対象になる。
{ config, lib, ... }:
let
  overlap = import ./lib/overlap.nix { inherit lib; };
  describeOverlap =
    pair: "  ${toString pair.a.id}(${pair.a.label}) と ${toString pair.b.id}(${pair.b.label})";
  invalidNodeLinks =
    workflow:
    let
      nodeIds = map (node: node.id) workflow.nodes;
    in
    builtins.filter (
      link:
      !(builtins.elem (builtins.elemAt link 1) nodeIds && builtins.elem (builtins.elemAt link 3) nodeIds)
    ) workflow.links;
  describeInvalidNodeLink =
    link:
    "  リンク${toString (builtins.elemAt link 0)}: ノード${toString (builtins.elemAt link 1)} → ノード${toString (builtins.elemAt link 3)}";
in
{
  config.assertions = lib.concatLists (
    lib.mapAttrsToList (name: workflow: [
      {
        assertion = invalidNodeLinks workflow == [ ];
        message = ''
          ComfyUIワークフロー${name}で以下のリンクが存在しないノードを参照しています:
          ${lib.concatMapStringsSep "\n" describeInvalidNodeLink (invalidNodeLinks workflow)}
        '';
      }
      {
        assertion = overlap.overlappingNodePairs workflow.nodes == [ ];
        message = ''
          ComfyUIワークフロー${name}で以下のノードが重なっています(余白${toString overlap.margin}px未満を含む):
          ${lib.concatMapStringsSep "\n" describeOverlap (overlap.overlappingNodePairs workflow.nodes)}
        '';
      }
    ]) config.local.comfyui.workflows
  );
}
