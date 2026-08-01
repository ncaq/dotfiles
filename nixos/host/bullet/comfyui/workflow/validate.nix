# 宣言された全ワークフローの構造とレイアウトを評価時に検証する。
#
# 存在しないノードへのリンクやノードの重なり、
# 実行順(`order`)の重複や依存への逆行はUIで開くまで気付きにくく、
# ノードを追加するたびに手動検証が漏れて何度も再発したため、
# NixOSのassertionsで機械的に検出する。
# `local.comfyui.workflows`を横断して検証するので、
# ワークフローを追加するだけで自動的に検証対象になる。
{ config, lib, ... }:
let
  link = import ./lib/link.nix { inherit lib; };
  linkTest = import ./lib/link-test.nix { inherit lib; };
  order = import ./lib/order.nix { inherit lib; };
  orderTest = import ./lib/order-test.nix { inherit lib; };
  overlap = import ./lib/overlap.nix { inherit lib; };
  overlapTest = import ./lib/overlap-test.nix { inherit lib; };
  describeOverlap =
    pair: "  ${toString pair.a.id}(${pair.a.label}) と ${toString pair.b.id}(${pair.b.label})";
  modelNames = lib.flatten (
    lib.mapAttrsToList (
      category:
      lib.mapAttrsToList (
        name: _:
        let
          categoryParts = lib.splitString "/" category;
        in
        [ name ]
        ++ lib.optional (
          1 < lib.length categoryParts
        ) "${lib.concatStringsSep "/" (lib.tail categoryParts)}/${name}"
      )
    ) config.local.comfyui.models
  );
in
assert linkTest;
assert orderTest;
assert overlapTest;
{
  config.assertions = lib.concatLists (
    lib.mapAttrsToList (
      name: workflow:
      let
        linkErrors = link.invalidReferences workflow;
        orderErrors = order.orderErrors workflow;
        overlappingNodePairs = overlap.overlappingNodePairs workflow.nodes;
        nodeIds = map (node: node.id) workflow.nodes;
        appInputs = workflow.extra.linearData.inputs or [ ];
        appOutputs = workflow.extra.linearData.outputs or [ ];
        invalidAppInputIds = lib.filter (id: !(lib.elem id nodeIds)) (map lib.head appInputs);
        invalidAppOutputIds = lib.filter (id: !(lib.elem id nodeIds)) appOutputs;
        referencedModels = lib.unique (
          lib.concatMap (
            node:
            lib.filter (
              widget: builtins.isString widget && builtins.match ".*\\.(safetensors|pt)" widget != null
            ) (node.widgets_values or [ ])
          ) workflow.nodes
        );
        missingModels = lib.filter (model: !(lib.elem model modelNames)) referencedModels;
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
          assertion = orderErrors == [ ];
          message = ''
            ComfyUIワークフロー${name}で以下のノード実行順が不整合です:
            ${lib.concatStringsSep "\n" orderErrors}
          '';
        }
        {
          assertion = overlappingNodePairs == [ ];
          message = ''
            ComfyUIワークフロー${name}で以下のノードが重なっています(余白${toString overlap.margin}px未満を含む):
            ${lib.concatMapStringsSep "\n" describeOverlap overlappingNodePairs}
          '';
        }
        {
          assertion = invalidAppInputIds == [ ];
          message = "ComfyUIワークフロー${name}のApp Mode入力が存在しないノードを参照しています: ${toString invalidAppInputIds}";
        }
        {
          assertion = invalidAppOutputIds == [ ];
          message = "ComfyUIワークフロー${name}のApp Mode出力が存在しないノードを参照しています: ${toString invalidAppOutputIds}";
        }
        {
          assertion = missingModels == [ ];
          message = "ComfyUIワークフロー${name}が未宣言のモデルを参照しています: ${toString missingModels}";
        }
      ]
    ) config.local.comfyui.workflows
  );
}
