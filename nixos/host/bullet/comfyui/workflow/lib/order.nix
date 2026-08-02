# ワークフローのノード実行順(`order`)の検証。
#
# `order`はUI形式のノードが持つ実行順の記録で、
# バックエンドは実際の実行順をリンクの依存関係から自前で決めるため、
# 値が壊れていてもワークフローは動いてしまう。
# しかし人間はこの値を読んで依存関係を追うので、
# 重複や依存に逆行した値は読み手を誤解させる。
# ノードを増減させるたびに手で振り直すと漏れるため機械的に検出する。
{ lib }:
{
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
}
