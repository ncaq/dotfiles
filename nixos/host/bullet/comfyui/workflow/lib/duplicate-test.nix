{ lib }:
let
  duplicate = import ./duplicate.nix { inherit lib; };
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
assert lib.assertMsg (duplicate.duplicateIdErrors validWorkflow == [ ]) "重複のないワークフローを拒否しました";
assert lib.assertMsg (
  duplicate.duplicateIdErrors duplicatedNodeWorkflow != [ ]
) "重複したノードIDを検出できませんでした";
assert lib.assertMsg (
  duplicate.duplicateIdErrors duplicatedLinkWorkflow != [ ]
) "重複したリンクIDを検出できませんでした";
true
