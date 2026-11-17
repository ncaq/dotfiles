# ワークフローのノード矩形の重なり検出。
#
# ComfyUIのノードの`pos`はタイトルバー左上の座標で、
# `size`は本体のみの寸法なので、
# 表示上の矩形はタイトルバーの高さを足したものになる。
# ぴったり接していても視覚的に窮屈なので、
# 余白が`margin`未満のペアも重なり扱いにする。
{ lib }:
let
  self = rec {
    # LiteGraphのNODE_TITLE_HEIGHT。
    titleHeight = 30;
    # ノード間に最低限確保する余白。
    margin = 10;

    # 宣言した`size`より下へ広がるノード種別と、その追加分の高さ。
    #
    # `size`はワークフローを開いた直後の寸法でしかなく、
    # フロントエンドが中身に応じてノードを下へ広げることがある。
    # 広がった状態は保存されないので`size`からは分からず、
    # 実際に使い始めてから初めて下のノードと重なる。
    # そのため重なり検出では最初からこの分も占有しているものとして扱い、
    # 下に別のノードを置けないようにする。
    growHeights = {
      # 動画を読み込むとプレビューがノードの下へ展開されて伸びる。
      # プレビューはノード幅いっぱいに元動画のアスペクト比で描かれるので、
      # 幅340のノードに縦長(2:3)の動画を読み込んだ場合の高さを見込む。
      LoadVideo = 500;
      # LoRA一覧の領域はフロントエンドが最小の高さを確保する。
      # LoRAを増やしても一覧の中がスクロールするだけでノードは伸びないが、
      # 確保される最小の高さは宣言した350より大きくなり得るため余裕を持たせる。
      "Lora Loader (LoraManager)" = 100;
    };
    growHeight = node: growHeights.${node.type} or 0;

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
          y1 = y0 + builtins.elemAt node.size 1 + titleHeight + growHeight node;
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
  };

  # 実装のテスト。全ての表明を通ると`true`になる。
  tests = {
    overlap =
      let
        overlap = self;
        validNodes = [
          {
            id = 1;
            type = "TestNode";
            pos = [
              0
              0
            ];
            size = [
              100
              100
            ];
          }
          {
            id = 2;
            type = "TestNode";
            pos = [
              200
              0
            ];
            size = [
              100
              100
            ];
          }
        ];
        overlappingNodes = map (
          node:
          if node.id == 2 then
            node
            // {
              pos = [
                50
                0
              ];
            }
          else
            node
        ) validNodes;
        # 実行時に下へ広がるノードの真下に、宣言サイズ基準では重ならないノードを置いた配置。
        # 広がりを見込まなければ余白があるように見えてしまう。
        growingType = "LoadVideo";
        growHeight = overlap.growHeights.${growingType};
        belowGrowingNodes = [
          {
            id = 1;
            type = growingType;
            pos = [
              0
              0
            ];
            size = [
              100
              100
            ];
          }
          {
            id = 2;
            type = "TestNode";
            pos = [
              0
              (100 + overlap.titleHeight + overlap.margin)
            ];
            size = [
              100
              100
            ];
          }
        ];
        # 広がりの分まで空けた配置。
        clearOfGrowingNodes = map (
          node:
          if node.id == 2 then
            node
            // {
              pos = [
                0
                (100 + overlap.titleHeight + overlap.margin + growHeight)
              ];
            }
          else
            node
        ) belowGrowingNodes;
        # ノード2をposへ動かした配置。境界値の検証に使う。
        moveSecondTo = pos: map (node: if node.id == 2 then node // { inherit pos; } else node) validNodes;
        # 横の余白がちょうどmarginの配置と、1px足りない配置。
        exactMarginNodes = moveSecondTo [
          (100 + overlap.margin)
          0
        ];
        underMarginNodes = moveSecondTo [
          (100 + overlap.margin - 1)
          0
        ];
        # 縦はタイトルバーの高さも占有に入る。
        verticalClearNodes = moveSecondTo [
          0
          (100 + overlap.titleHeight + overlap.margin)
        ];
        verticalTightNodes = moveSecondTo [
          0
          (100 + overlap.titleHeight + overlap.margin - 1)
        ];
      in
      assert lib.assertMsg (overlap.overlappingNodePairs validNodes == [ ]) "重なっていないノードを拒否しました";
      assert lib.assertMsg (overlap.overlappingNodePairs overlappingNodes != [ ]) "重なったノードを検出できませんでした";
      assert lib.assertMsg (
        overlap.overlappingNodePairs belowGrowingNodes != [ ]
      ) "下へ広がるノードの真下のノードを検出できませんでした";
      assert lib.assertMsg (
        overlap.overlappingNodePairs clearOfGrowingNodes == [ ]
      ) "下へ広がる分を空けた配置を拒否しました";
      assert lib.assertMsg (
        overlap.overlappingNodePairs exactMarginNodes == [ ]
      ) "横の余白がちょうどmarginの配置を拒否しました";
      assert lib.assertMsg (
        overlap.overlappingNodePairs underMarginNodes != [ ]
      ) "横の余白がmarginに足りない配置を検出できませんでした";
      assert lib.assertMsg (
        overlap.overlappingNodePairs verticalClearNodes == [ ]
      ) "縦の余白がちょうどmarginの配置を拒否しました";
      assert lib.assertMsg (
        overlap.overlappingNodePairs verticalTightNodes != [ ]
      ) "タイトルバーの高さの分だけ縦の余白が足りない配置を検出できませんでした";
      true;
  };
in
assert lib.all lib.id (lib.attrValues tests);
self
