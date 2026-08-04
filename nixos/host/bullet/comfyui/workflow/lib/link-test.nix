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
  # スロットの型をtypeへ差し替えたワークフローを作る。
  withInputType = type: {
    inherit (validWorkflow) links;
    nodes = map (
      node:
      if node.id == 2 then
        node
        // {
          inputs = [
            {
              inherit type;
              link = 1;
            }
          ];
        }
      else
        node
    ) validWorkflow.nodes;
  };
  # ワイルドカード型のスロットはどの型のリンクも受け入れる。
  wildcardWorkflow = withInputType "*";
  # カンマ区切りの複数型のスロットは列挙された型のリンクだけ受け入れる。
  multiTypeWorkflow = withInputType "TEST,OTHER";
  multiTypeMismatchWorkflow = withInputType "OTHER,ANOTHER";
  # 存在しないノードを接続先に指すリンク。
  missingNodeWorkflow = validWorkflow // {
    links = [
      [
        1
        1
        0
        3
        0
        "TEST"
      ]
    ];
  };
in
assert lib.assertMsg (link.invalidReferences validWorkflow == [ ]) "正常なワークフローを拒否しました";
assert lib.assertMsg (link.invalidReferences brokenWorkflow != [ ]) "壊れたワークフローを検出できませんでした";
assert lib.assertMsg (link.invalidReferences invalidSlotWorkflow != [ ]) "範囲外のスロットを検出できませんでした";
assert lib.assertMsg (link.invalidReferences invalidTypeWorkflow != [ ]) "一致しないリンク型を検出できませんでした";
assert lib.assertMsg (link.invalidReferences wildcardWorkflow == [ ]) "ワイルドカード型のスロットを拒否しました";
assert lib.assertMsg (link.invalidReferences multiTypeWorkflow == [ ]) "複数型のスロットへの一致する型のリンクを拒否しました";
assert lib.assertMsg (
  link.invalidReferences multiTypeMismatchWorkflow != [ ]
) "複数型のスロットのどの型とも一致しないリンクを検出できませんでした";
assert lib.assertMsg (
  link.invalidReferences missingNodeWorkflow != [ ]
) "存在しないノードを指すリンクを検出できませんでした";
true
