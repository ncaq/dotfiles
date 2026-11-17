# ワークフローのノード実行順(`order`)の検証。
#
# `order`はUI形式のノードが持つ実行順の記録で、
# バックエンドは実際の実行順をリンクの依存関係から自前で決めるため、
# 値が壊れていてもワークフローは動いてしまう。
# しかし人間はこの値を読んで依存関係を追うので、
# 重複や依存に逆行した値は読み手を誤解させる。
# ノードを増減させるたびに手で振り直すと漏れるため機械的に検出する。
{ lib }:
let
  # ノードの`order`に関する問題のメッセージのリストを返す。
  # 問題がなければ空リスト。
  orderErrors =
    workflow:
    let
      findNode = id: lib.findFirst (node: node.id == id) null workflow.nodes;
      label = node: node.title or node.type;
      describe = node: "${toString node.id}(${label node})";

      # 同じorderを持つノードが複数ある場合を検出する。
      # orderはノードごとに一意でなければ実行順の記録として意味を持たない。
      duplicateErrors =
        let
          byOrder = lib.groupBy (node: toString node.order) workflow.nodes;
          duplicated = lib.filterAttrs (_: nodes: 1 < builtins.length nodes) byOrder;
        in
        lib.mapAttrsToList (
          order: nodes: "  order=${order}がノード${lib.concatMapStringsSep ", " describe nodes}で重複しています"
        ) duplicated;

      # リンクの向きとorderの大小が逆転している場合を検出する。
      # 接続元は接続先より先に実行されるので、必ずorderが小さくなる。
      topologyErrors = lib.concatMap (
        link:
        let
          sourceNode = findNode (builtins.elemAt link 1);
          targetNode = findNode (builtins.elemAt link 3);
        in
        lib.optional (sourceNode != null && targetNode != null && targetNode.order <= sourceNode.order)
          "  ノード${describe sourceNode}のorder=${toString sourceNode.order}が、接続先のノード${describe targetNode}のorder=${toString targetNode.order}より後です"
      ) workflow.links;
    in
    duplicateErrors ++ topologyErrors;

  # 以下は末尾の`assert`のための入力。
  validWorkflow = {
    nodes = [
      {
        id = 1;
        type = "TestNode";
        order = 0;
      }
      {
        id = 2;
        type = "TestNode";
        order = 1;
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
    ];
  };
  duplicatedWorkflow = validWorkflow // {
    nodes = map (node: if node.id == 2 then node // { order = 0; } else node) validWorkflow.nodes;
  };
  reversedWorkflow = validWorkflow // {
    nodes = map (node: if node.id == 1 then node // { order = 2; } else node) validWorkflow.nodes;
  };
  # リンクで繋がっていないノード同士の重複。
  # 依存の逆行検出はリンクを見るので、重複検出が独立して働くことを確かめる。
  unlinkedDuplicatedWorkflow = {
    nodes = map (node: node // { order = 0; }) validWorkflow.nodes;
    links = [ ];
  };
in
assert lib.assertMsg (orderErrors validWorkflow == [ ]) "正常なorderを拒否しました";
assert lib.assertMsg (orderErrors duplicatedWorkflow != [ ]) "重複したorderを検出できませんでした";
assert lib.assertMsg (orderErrors reversedWorkflow != [ ]) "依存に逆行したorderを検出できませんでした";
assert lib.assertMsg (
  orderErrors unlinkedDuplicatedWorkflow != [ ]
) "リンクのないノード同士の重複したorderを検出できませんでした";
{
  inherit orderErrors;
}
