{ lib }:
let
  link = import ./link.nix { inherit lib; };
  validWorkflow = {
    nodes = [
      {
        id = 1;
        inputs = [ ];
        outputs = [
          {
            type = "TEST";
            links = [ 1 ];
          }
        ];
      }
      {
        id = 2;
        inputs = [
          {
            type = "TEST";
            link = 1;
          }
        ];
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
      node:
      if node.id == 2 then
        node
        // {
          inputs = [
            {
              type = "TEST";
              link = 2;
            }
          ];
        }
      else
        node
    ) validWorkflow.nodes;
  };
  invalidSlotWorkflow = validWorkflow // {
    links = [
      [
        1
        1
        1
        2
        0
        "TEST"
      ]
    ];
  };
  invalidTypeWorkflow = validWorkflow // {
    links = [
      [
        1
        1
        0
        2
        0
        "OTHER"
      ]
    ];
  };
in
assert lib.assertMsg (link.invalidReferences validWorkflow == [ ]) "正常なワークフローを拒否しました";
assert lib.assertMsg (link.invalidReferences brokenWorkflow != [ ]) "壊れたワークフローを検出できませんでした";
assert lib.assertMsg (link.invalidReferences invalidSlotWorkflow != [ ]) "範囲外のスロットを検出できませんでした";
assert lib.assertMsg (link.invalidReferences invalidTypeWorkflow != [ ]) "一致しないリンク型を検出できませんでした";
true
