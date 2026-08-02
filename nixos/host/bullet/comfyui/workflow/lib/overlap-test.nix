{ lib }:
let
  overlap = import ./overlap.nix { inherit lib; };
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
in
assert lib.assertMsg (overlap.overlappingNodePairs validNodes == [ ]) "重なっていないノードを拒否しました";
assert lib.assertMsg (overlap.overlappingNodePairs overlappingNodes != [ ]) "重なったノードを検出できませんでした";
assert lib.assertMsg (
  overlap.overlappingNodePairs belowGrowingNodes != [ ]
) "下へ広がるノードの真下のノードを検出できませんでした";
assert lib.assertMsg (
  overlap.overlappingNodePairs clearOfGrowingNodes == [ ]
) "下へ広がる分を空けた配置を拒否しました";
true
