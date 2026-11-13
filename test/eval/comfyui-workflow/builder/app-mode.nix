# App Modeの入力と出力の定義の形式を検証する。
{ lib }:
let
  builder = import ../../../../nixos/host/bullet/comfyui/workflow/lib/builder.nix { inherit lib; };

  appMeta = {
    inputs = [ (builder.mkAppInput 1 "seed") ];
    outputs = [ 1 ];
  };
  appWorkflow = builder.mkWorkflow {
    nodes = [
      (builder.mkNode {
        id = 1;
        type = "TestNode";
        pos = [
          0
          0
        ];
        size = [
          10
          10
        ];
        order = 0;
      })
    ];
    links = [ ];
    app = appMeta;
  };
in
# App Mode入力は[ノードID ウィジェット名 設定?]の配列で表現される。
assert lib.assertMsg (
  builder.mkAppInput 1 "seed" == [
    1
    "seed"
  ]
) "App Mode入力の形式が想定と違います";
assert lib.assertMsg (
  builder.mkAppInputWith 1 "seed" { height = 100; } == [
    1
    "seed"
    { height = 100; }
  ]
) "設定付きApp Mode入力の形式が想定と違います";
assert lib.assertMsg (
  appWorkflow.extra.linearMode == false && appWorkflow.extra.linearData == appMeta
) "App Mode定義がextraへ反映されていません";
true
