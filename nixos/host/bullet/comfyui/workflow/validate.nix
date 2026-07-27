# 宣言された全ワークフローのレイアウトを評価時に検証する。
#
# ノードの重なりはUIで開くまで気付きにくく、
# ノードを追加するたびに手動検証が漏れて何度も再発したため、
# NixOSのassertionsで機械的に検出する。
# `local.comfyui.workflows`を横断して検証するので、
# ワークフローを追加するだけで自動的に検証対象になる。
{ config, lib, ... }:
let
  overlap = import ./lib/overlap.nix { inherit lib; };
  describe =
    pair: "  ${toString pair.a.id}(${pair.a.label}) と ${toString pair.b.id}(${pair.b.label})";
in
{
  config.assertions = lib.mapAttrsToList (name: workflow: {
    assertion = overlap.overlappingNodePairs workflow.nodes == [ ];
    message = ''
      ComfyUIワークフロー${name}で以下のノードが重なっています(余白${toString overlap.margin}px未満を含む):
      ${lib.concatMapStringsSep "\n" describe (overlap.overlappingNodePairs workflow.nodes)}
    '';
  }) config.local.comfyui.workflows;
}
