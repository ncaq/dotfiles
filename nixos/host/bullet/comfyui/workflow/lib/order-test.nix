{ lib }:
let
  order = import ./order.nix { inherit lib; };
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
in
assert lib.assertMsg (order.orderErrors validWorkflow == [ ]) "正常なorderを拒否しました";
assert lib.assertMsg (order.orderErrors duplicatedWorkflow != [ ]) "重複したorderを検出できませんでした";
assert lib.assertMsg (order.orderErrors reversedWorkflow != [ ]) "依存に逆行したorderを検出できませんでした";
true
