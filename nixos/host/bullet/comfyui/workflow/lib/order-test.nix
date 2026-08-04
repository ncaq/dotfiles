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
  # リンクで繋がっていないノード同士の重複。
  # 依存の逆行検出はリンクを見るので、重複検出が独立して働くことを確かめる。
  unlinkedDuplicatedWorkflow = {
    nodes = map (node: node // { order = 0; }) validWorkflow.nodes;
    links = [ ];
  };
in
assert lib.assertMsg (order.orderErrors validWorkflow == [ ]) "正常なorderを拒否しました";
assert lib.assertMsg (order.orderErrors duplicatedWorkflow != [ ]) "重複したorderを検出できませんでした";
assert lib.assertMsg (order.orderErrors reversedWorkflow != [ ]) "依存に逆行したorderを検出できませんでした";
assert lib.assertMsg (
  order.orderErrors unlinkedDuplicatedWorkflow != [ ]
) "リンクのないノード同士の重複したorderを検出できませんでした";
true
