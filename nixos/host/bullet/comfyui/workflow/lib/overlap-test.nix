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
in
assert lib.assertMsg (overlap.overlappingNodePairs validNodes == [ ]) "重なっていないノードを拒否しました";
assert lib.assertMsg (overlap.overlappingNodePairs overlappingNodes != [ ]) "重なったノードを検出できませんでした";
true
