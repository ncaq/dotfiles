{ lib }:
let
  link = import ./link.nix { inherit lib; };
  validWorkflow = {
    nodes = [
      {
        id = 1;
        inputs = [ ];
        outputs = [ { links = [ 1 ]; } ];
      }
      {
        id = 2;
        inputs = [ { link = 1; } ];
        outputs = [ ];
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
  brokenWorkflow = validWorkflow // {
    nodes = map (
      node: if node.id == 2 then node // { inputs = [ { link = 2; } ]; } else node
    ) validWorkflow.nodes;
  };
in
assert lib.assertMsg (link.invalidReferences validWorkflow == [ ]) "正常なワークフローを拒否しました";
assert lib.assertMsg (link.invalidReferences brokenWorkflow != [ ]) "壊れたワークフローを検出できませんでした";
true
