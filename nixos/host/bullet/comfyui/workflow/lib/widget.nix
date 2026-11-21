# App Mode(linearData)の入力が指すウィジェット名の検証。
#
# App Mode入力はウィジェットをスロット番号ではなく名前で指すため、
# ノード型を差し替えて名前が変わっても参照側は古い名前のまま残る。
# 実際にKSamplerをKSamplerAdvancedへ替えた時、
# `seed`が`noise_seed`へ、`denoise`が`start_at_step`へ変わっている。
# 名前の合わない入力はApp Modeの画面に出ないだけで警告もされないので、
# App Modeを開いて初めて気付くことになる。
#
# `lib/builder.nix`の`promptNodes`はdenoiseの値でノード型を選ぶため、
# 同じノードID 5がKSamplerにもKSamplerAdvancedにもなる。
# ノード型は計算で決まるのにウィジェット名は呼び出し元が手で書くので、
# この食い違いは今後も繰り返し起きる。
#
# ワークフローJSONの`widgets_values`は値だけを並べた配列で名前を持たないため、
# 正しい名前を知るにはノード定義の情報が要る。
# ComfyUIのノード定義は評価時に参照できないので`widgetNames`へ書き写す。
{ lib }:
let
  # ノード型ごとのウィジェット名。
  #
  # ノード定義のINPUT_TYPESのうち、
  # ソケットではなくウィジェットとして描かれる入力の名前を定義順に並べる。
  # MODELやIMAGEのようにソケットでしか繋げない入力は含めない。
  # フロントエンドが足すseedの実行後の挙動や画像のアップロードボタンは、
  # ノード定義には無くApp Modeからも指せないので含めない。
  # そのため`widgets_values`とは要素数が違い、あちらの検証には使えない。
  #
  # App Modeから参照するノード型だけを載せれば良い。
  widgetNames = {
    CLIPTextEncode = [ "text" ];
    EmptyLatentImage = [
      "width"
      "height"
      "batch_size"
    ];
    ImageScaleToTotalPixels = [
      "upscale_method"
      "megapixels"
      "resolution_steps"
    ];
    KSampler = [
      "seed"
      "steps"
      "cfg"
      "sampler_name"
      "scheduler"
      "denoise"
    ];
    KSamplerAdvanced = [
      "add_noise"
      "noise_seed"
      "steps"
      "cfg"
      "sampler_name"
      "scheduler"
      "start_at_step"
      "end_at_step"
      "return_with_leftover_noise"
    ];
    LoadImage = [ "image" ];
    # 自作ノード。`pkgs/comfyui-ncaq-nodes/src/load_image_optional.py`。
    LoadImageOptional = [ "image" ];
    # 動画を選ぶウィジェットは画像と違って`file`。
    LoadVideo = [ "file" ];
    PrimitiveFloat = [ "value" ];
    PrimitiveInt = [ "value" ];
    RandomNoise = [ "noise_seed" ];
    # 自作ノード。`pkgs/comfyui-ncaq-nodes/src/rewrite_edit_prompt.py`。
    RewriteEditPrompt = [
      "text"
      "seed"
      "resolution"
    ];
    # 自作ノード。`pkgs/comfyui-ncaq-nodes/src/translate_text.py`。
    TranslateTextToEnglish = [
      "text"
      "context"
    ];
    UNETLoader = [
      "unet_name"
      "weight_dtype"
    ];
  };

  # App Mode入力のウィジェット名に関する問題のメッセージのリストを返す。
  # 問題がなければ空リスト。
  appInputWidgetErrors =
    workflow:
    let
      findNode = id: lib.findFirst (node: node.id == id) null workflow.nodes;
      label = node: node.title or node.type;
    in
    lib.concatMap (
      input:
      let
        nodeId = builtins.elemAt input 0;
        widgetName = builtins.elemAt input 1;
        node = findNode nodeId;
        names = widgetNames.${node.type} or null;
      in
      # 存在しないノードIDは別のassertionが報告するので二重に報告しない。
      if node == null then
        [ ]
      # 知らないノード型を素通しすると、
      # ノード型を差し替えた瞬間という一番壊れやすい時に検証が消えるため、
      # 表への追記を促すエラーにする。
      else if names == null then
        [
          "  ノード${toString nodeId}(${label node})の型${node.type}が`lib/widget.nix`の`widgetNames`にありません"
        ]
      else
        lib.optional (!(lib.elem widgetName names))
          "  ノード${toString nodeId}(${label node})の${widgetName}は${node.type}のウィジェットにありません(${lib.concatStringsSep ", " names})"
    ) (workflow.extra.linearData.inputs or [ ]);

  # 以下は末尾の`assert`のための入力。
  # App Mode入力は、ワークフローが実際に使う`builder`の関数で組み立てる。
  builder = import ./builder.nix { inherit lib; };
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
assert lib.assertMsg (appInputWidgetErrors validWorkflow == [ ]) "正しいウィジェット名のApp Mode入力を拒否しました";
assert lib.assertMsg (appInputWidgetErrors noAppWorkflow == [ ]) "App Modeを持たないワークフローを拒否しました";
assert lib.assertMsg (
  appInputWidgetErrors missingNodeWorkflow == [ ]
) "存在しないノードIDをウィジェット名の検証が報告しました";
assert lib.assertMsg (
  appInputWidgetErrors renamedWidgetWorkflow != [ ]
) "ノード型に無いウィジェット名を検出できませんでした";
assert lib.assertMsg (
  appInputWidgetErrors renamedWidgetWithConfigWorkflow != [ ]
) "設定付き入力のウィジェット名を検出できませんでした";
assert lib.assertMsg (
  appInputWidgetErrors unknownTypeWorkflow != [ ]
) "widgetNamesに載っていないノード型を検出できませんでした";
{
  inherit widgetNames appInputWidgetErrors;
}
