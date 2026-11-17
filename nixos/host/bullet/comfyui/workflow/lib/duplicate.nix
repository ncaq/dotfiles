# ワークフローのノードIDとリンクIDの重複の検証。
#
# IDが重複してもリンクの参照検証は素通りする。
# `lib/link.nix`の探索が`lib.findFirst`で先頭だけを返すため、
# 後から同じIDを振ったノードやリンクは存在しないのと同じ扱いになり、
# 参照は先頭のものへ解決されて整合しているように見えてしまう。
# `mkWorkflow`の`last_node_id`と`last_link_id`も最大値から算出するので、
# 重複したままUIで開くとノードやリンクの追加時にIDが衝突する。
#
# `lib/builder.nix`の`promptNodes`のように、
# 呼び出し元と共有部品でIDの割り当てを分担している構造では、
# 片方が使う範囲を広げた時に静かに衝突するため機械的に検出する。
{ lib }:
let
  # ノードIDとリンクIDの重複のメッセージのリストを返す。
  # 問題がなければ空リスト。
  duplicateIdErrors =
    workflow:
    let
      label = node: node.title or node.type;
      describeNode = node: "${toString node.id}(${label node})";
      # 重複しているIDごとに、そのIDを持つ要素をまとめて返す。
      duplicatedBy =
        id: items:
        lib.filterAttrs (_: duplicated: 1 < builtins.length duplicated) (
          lib.groupBy (item: toString (id item)) items
        );
      nodeErrors = lib.mapAttrsToList (
        id: nodes: "  ノードID=${id}がノード${lib.concatMapStringsSep ", " describeNode nodes}で重複しています"
      ) (duplicatedBy (node: node.id) workflow.nodes);
      linkErrors = lib.mapAttrsToList (
        id: links: "  リンクID=${id}が${toString (builtins.length links)}本のリンクで重複しています"
      ) (duplicatedBy lib.head workflow.links);
    in
    nodeErrors ++ linkErrors;

  # 以下は末尾の`assert`のための入力。
  validWorkflow = {
    nodes = [
      {
        id = 1;
        type = "TestNode";
      }
      {
        id = 2;
        type = "TestNode";
      }
    ];
    links = [
      [
        1
        1
        0
        2
        0
        "TEST"
      ]
      [
        2
        1
        1
        2
        1
        "TEST"
      ]
    ];
  };
  duplicatedNodeWorkflow = validWorkflow // {
    nodes = map (node: if node.id == 2 then node // { id = 1; } else node) validWorkflow.nodes;
  };
  duplicatedLinkWorkflow = validWorkflow // {
    links = map (link: [ 1 ] ++ lib.tail link) validWorkflow.links;
  };
in
assert lib.assertMsg (duplicateIdErrors validWorkflow == [ ]) "重複のないワークフローを拒否しました";
assert lib.assertMsg (duplicateIdErrors duplicatedNodeWorkflow != [ ]) "重複したノードIDを検出できませんでした";
assert lib.assertMsg (duplicateIdErrors duplicatedLinkWorkflow != [ ]) "重複したリンクIDを検出できませんでした";
{
  inherit duplicateIdErrors;
}
