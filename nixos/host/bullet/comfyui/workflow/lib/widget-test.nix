{ lib }:
let
  builder = import ./builder.nix { inherit lib; };
  widget = import ./widget.nix { inherit lib; };
  nodes = [
    {
      id = 5;
      type = "KSamplerAdvanced";
    }
    {
      id = 9;
      type = "LoadImage";
      title = "編集する画像";
    }
    {
      id = 12;
      type = "SaveImage";
    }
  ];
  withAppInputs = inputs: {
    inherit nodes;
    extra.linearData = { inherit inputs; };
  };
  validWorkflow = withAppInputs [
    (builder.mkAppInput 5 "noise_seed")
    (builder.mkAppInputWith 5 "start_at_step" { description = "どこから描き直すか"; })
    (builder.mkAppInput 9 "image")
  ];
  # App Modeを持たないワークフロー。
  noAppWorkflow = {
    inherit nodes;
    extra = { };
  };
  # 存在しないノードIDを指す入力。
  # ノードIDの存在は別のassertionが見るので、こちらは報告しない。
  missingNodeWorkflow = withAppInputs [ (builder.mkAppInput 99 "noise_seed") ];
  # KSamplerAdvancedへ替えた時に直し忘れるウィジェット名。
  renamedWidgetWorkflow = withAppInputs [ (builder.mkAppInput 5 "seed") ];
  # 設定付きの入力でも同じように検出できるかの確認。
  renamedWidgetWithConfigWorkflow = withAppInputs [
    (builder.mkAppInputWith 5 "denoise" { description = "元画像を変える強さ"; })
  ];
  # 表に載っていないノード型を指す入力。
  unknownTypeWorkflow = withAppInputs [ (builder.mkAppInput 12 "filename_prefix") ];
in
assert lib.assertMsg (
  widget.appInputWidgetErrors validWorkflow == [ ]
) "正しいウィジェット名のApp Mode入力を拒否しました";
assert lib.assertMsg (
  widget.appInputWidgetErrors noAppWorkflow == [ ]
) "App Modeを持たないワークフローを拒否しました";
assert lib.assertMsg (
  widget.appInputWidgetErrors missingNodeWorkflow == [ ]
) "存在しないノードIDをウィジェット名の検証が報告しました";
assert lib.assertMsg (
  widget.appInputWidgetErrors renamedWidgetWorkflow != [ ]
) "ノード型に無いウィジェット名を検出できませんでした";
assert lib.assertMsg (
  widget.appInputWidgetErrors renamedWidgetWithConfigWorkflow != [ ]
) "設定付き入力のウィジェット名を検出できませんでした";
assert lib.assertMsg (
  widget.appInputWidgetErrors unknownTypeWorkflow != [ ]
) "widgetNamesに載っていないノード型を検出できませんでした";
true
