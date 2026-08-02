# ワークフローのノード矩形の重なり検出。
#
# ComfyUIのノードの`pos`はタイトルバー左上の座標で、
# `size`は本体のみの寸法なので、
# 表示上の矩形はタイトルバーの高さを足したものになる。
# ぴったり接していても視覚的に窮屈なので、
# 余白が`margin`未満のペアも重なり扱いにする。
{ lib }:
rec {
  # LiteGraphのNODE_TITLE_HEIGHT。
  titleHeight = 30;
  # ノード間に最低限確保する余白。
  margin = 10;

  # ノードのリストから重なっているペア{a, b}のリストを返す。
  # aとbは{id, label, x0, y0, x1, y1}の矩形情報。
  overlappingNodePairs =
    nodes:
    let
      rect = node: rec {
        inherit (node) id;
        label = node.title or node.type;
        x0 = builtins.elemAt node.pos 0;
        y0 = builtins.elemAt node.pos 1;
        x1 = x0 + builtins.elemAt node.size 0;
        y1 = y0 + builtins.elemAt node.size 1 + titleHeight;
      };
      intersects =
        a: b: a.x0 < b.x1 + margin && b.x0 < a.x1 + margin && a.y0 < b.y1 + margin && b.y0 < a.y1 + margin;
      rects = map rect nodes;
      n = builtins.length rects;
    in
    lib.concatMap (
      i:
      lib.concatMap (
        j:
        let
          a = builtins.elemAt rects i;
          b = builtins.elemAt rects j;
        in
        lib.optional (intersects a b) { inherit a b; }
      ) (lib.range (i + 1) (n - 1))
    ) (lib.range 0 (n - 1));
}
