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
rec {
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
    # 自作ノード。`custom-node/align-image-size/__init__.py`。
    AlignImageDimensions = [
      "width"
      "height"
      "multiple"
    ];
    # 自作ノード。`custom-node/anime-video-quick/__init__.py`。
    AnimeVideoQuick = [
      "prompts"
      "wan_model_high"
      "wan_model_low"
      "wan_clip"
      "wan_vae"
      "seed"
      "retry_seed_offset"
      "job_id"
    ];
    CLIPTextEncode = [ "text" ];
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
    # 自作ノード。`custom-node/load-image-optional/__init__.py`。
    LoadImageOptional = [ "image" ];
    # 動画を選ぶウィジェットは画像と違って`file`。
    LoadVideo = [ "file" ];
    PrimitiveInt = [ "value" ];
    # 自作ノード。`custom-node/translate-text/__init__.py`。
    TranslateTextToEnglish = [ "text" ];
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
}
