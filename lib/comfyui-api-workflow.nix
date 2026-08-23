/**
  Open WebUIへ環境変数として渡すComfyUIのAPI形式ワークフローを、
  評価時に検査してassertionのリストを返す。

  ComfyUIのワークフローにはUI形式とAPI形式があり、
  bulletが持つUI形式は`comfyui/workflow/lib/validate.nix`が、
  リンク切れやID重複やウィジェットの並びを機械的に弾いている。
  API形式は構造が違うのでその検査を流用できない。

  検査が無いと、
  接続先のIDを打ち間違えても、
  `workflowNodes`が存在しないノードを指していても、
  `key`が対象ノードの`inputs`に無くても、
  評価は素通りしてComfyUIの実行時にしか分からない。

  しかもOpen WebUI経由では最も気付きにくい壊れ方をする。
  画像を返す保存ノードへ至る経路だけがバリデーションで落ちて、
  そこを通らないノードは生き残るため、
  全体の`status`は`success`のまま画像だけが返らない。

  ```nix
  assertions = import ../../../../lib/comfyui-api-workflow.nix { inherit lib; } {
    name = "画像生成";
    inherit workflow workflowNodes;
  };
  ```
*/
{ lib }:
{
  # エラーメッセージでどちらのワークフローかを示す名前。
  name,
  # ノードIDをキーに`class_type`と`inputs`を持つAPI形式のワークフロー。
  workflow,
  # UIの入力をワークフローのどのノードへ流し込むかの対応。
  workflowNodes,
}:
let
  nodeIds = lib.attrNames workflow;

  # API形式では他のノードへの接続を`[ノードID, 出力スロット]`で表す。
  # ウィジェットの値はスカラなのでこの形と衝突しない。
  isLink = value: lib.isList value && lib.length value == 2 && lib.isString (lib.elemAt value 0);

  links = lib.concatMap (
    id:
    lib.concatMap (
      inputName:
      let
        value = workflow.${id}.inputs.${inputName};
      in
      lib.optional (isLink value) {
        inherit id inputName;
        target = lib.elemAt value 0;
      }
    ) (lib.attrNames workflow.${id}.inputs)
  ) nodeIds;

  dangling = lib.filter (link: !(lib.elem link.target nodeIds)) links;

  # `workflowNodes`のうち、存在しないノードを指しているもの。
  missingNodes = lib.concatMap (
    entry:
    map (nodeId: "${entry.type} -> ${nodeId}") (
      lib.filter (nodeId: !(lib.elem nodeId nodeIds)) entry.node_ids
    )
  ) workflowNodes;

  # `workflowNodes`のうち、対象ノードが`key`を持たないもの。
  # 存在しないノードは`missingNodes`が報告するのでここでは除く。
  missingKeys = lib.concatMap (
    entry:
    map (nodeId: "${entry.type} -> ${nodeId}.${entry.key}") (
      lib.filter (
        nodeId: lib.elem nodeId nodeIds && !(workflow.${nodeId}.inputs ? ${entry.key})
      ) entry.node_ids
    )
  ) workflowNodes;
in
[
  {
    assertion = dangling == [ ];
    message = "${name}のワークフローが存在しないノードへ接続しています: ${
      lib.concatMapStringsSep ", " (link: "${link.id}.${link.inputName} -> ${link.target}") dangling
    }";
  }
  {
    assertion = missingNodes == [ ];
    message = "${name}のworkflowNodesが存在しないノードを指しています: ${lib.concatStringsSep ", " missingNodes}";
  }
  {
    assertion = missingKeys == [ ];
    message = "${name}のworkflowNodesが対象ノードの持たない入力を指しています: ${lib.concatStringsSep ", " missingKeys}";
  }
]
