# `lib/builder.nix`の共有部品の形状を検証する。
#
# `Lora Loader (LoraManager)`は入力スロットの並びとウィジェットの並びが、
# LoRA Manager側のノード定義と一致していないと、
# 管理画面のSend to Workflowがこのノードを見つけられず動かなくなる。
# 他のassertionはリンクやorderしか見ないため、
# 綴りや並びが崩れてもビルドは通ってUIで開くまで気付けない。
#
# `promptNodes`と`promptLinks`は全ワークフローの土台なので、
# 引数がノードへ反映されることと、
# 呼び出し元が最低限の後続ノードを足した状態で、
# ID重複・リンク・order・重なりの各検証を通ることも確かめる。
{ lib }:
let
  builder = import ./builder.nix { inherit lib; };
  duplicate = import ./duplicate.nix { inherit lib; };
  link = import ./link.nix { inherit lib; };
  order = import ./order.nix { inherit lib; };
  overlap = import ./overlap.nix { inherit lib; };
  # CLIPも通す場合。
  withClip = builder.mkLoraLoader {
    id = 16;
    pos = [
      0
      0
    ];
    order = 1;
    modelLink = 28;
    clipLink = 29;
    modelLinks = [ 1 ];
    clipLinks = [
      2
      3
    ];
  };
  # UNETにだけ作用するLoRA向けにCLIPを繋がない場合。
  withoutClip = builder.mkLoraLoader {
    id = 31;
    title = "LoRA(high noise用)";
    pos = [
      0
      0
    ];
    order = 1;
    modelLink = 38;
    modelLinks = [ 1 ];
  };
  slotNames = map (slot: slot.name);
  slotTypes = map (slot: slot.type);

  findNode = nodes: id: lib.findFirst (node: node.id == id) null nodes;
  outputLinks =
    nodes: id: slot:
    (lib.elemAt (findNode nodes id).outputs slot).links;

  # オプション引数を全て省略した素のノード。
  plainNode = builder.mkNode {
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
  };

  # `promptNodes`が要求する後続ノード(リンク7と8の受け手)を足した最小構成。
  # 呼び出し元が最低限やることの再現になっている。
  promptWorkflow = builder.mkWorkflow {
    nodes = builder.promptNodes { } ++ [
      (builder.mkNode {
        id = 6;
        type = "VAEDecode";
        pos = [
          1290
          200
        ];
        size = [
          210
          46
        ];
        order = 6;
        inputs = [
          (builder.mkInput "samples" "LATENT" 7)
          (builder.mkInput "vae" "VAE" 8)
        ];
        outputs = [ (builder.mkOutput "IMAGE" "IMAGE" [ ]) ];
      })
    ];
    links = builder.promptLinks;
  };

  # img2img向けの構成。EmptyLatentImageを省いてKSamplerのorderをずらす。
  img2imgNodes = builder.promptNodes {
    withEmptyLatent = false;
    samplerOrder = 7;
    denoise = 0.5;
  };
  img2imgSampler = findNode img2imgNodes 5;

  # 追加リンクは共通ノードの出力の既定リンクの後ろへ足される。
  extraNodes = builder.promptNodes {
    extraModelLinks = [ 90 ];
    extraClipLinks = [ 91 ];
    extraVaeLinks = [ 92 ];
    extraPositiveLinks = [ 93 ];
    extraNegativeLinks = [ 94 ];
  };

  appMeta = {
    inputs = [ (builder.mkAppInput 1 "seed") ];
    outputs = [ 1 ];
  };
  appWorkflow = builder.mkWorkflow {
    nodes = [ plainNode ];
    links = [ ];
    app = appMeta;
  };
in
assert lib.assertMsg (withClip.type == "Lora Loader (LoraManager)") "ノード型が想定と違います";
assert lib.assertMsg (
  slotNames withClip.inputs == [
    "model"
    "text"
    "clip"
    "lora_stack"
  ]
) "入力スロットの名前か並びが想定と違います";
assert lib.assertMsg (
  slotTypes withClip.inputs == [
    "MODEL"
    "AUTOCOMPLETE_TEXT_LORAS"
    "CLIP"
    "LORA_STACK"
  ]
) "入力スロットの型が想定と違います";
assert lib.assertMsg (
  slotNames withClip.outputs == [
    "MODEL"
    "CLIP"
    "trigger_words"
    "loaded_loras"
  ]
) "出力スロットの名前か並びが想定と違います";
# LoRA一覧の内部状態、テキスト、有効なLoRAのリストの順。
assert lib.assertMsg (
  withClip.widgets_values == [
    {
      version = 1;
      textWidgetName = "text";
    }
    ""
    [ ]
  ]
) "ウィジェットの内容か並びが想定と違います";
# textスロットはウィジェットと連動する入力なのでwidget属性が要る。
assert lib.assertMsg (
  (lib.elemAt withClip.inputs 1).widget.name == "text"
) "textスロットのwidget名が想定と違います";
# オプション入力はshape 7で描かれる。
assert lib.assertMsg (
  (lib.elemAt withClip.inputs 2).shape == 7 && (lib.elemAt withClip.inputs 3).shape == 7
) "オプション入力のshapeが想定と違います";
assert lib.assertMsg (
  (lib.elemAt withClip.inputs 0).link == 28 && (lib.elemAt withClip.inputs 2).link == 29
) "入力リンクが引数どおりに設定されていません";
assert lib.assertMsg (
  (lib.elemAt withClip.outputs 0).links == [ 1 ]
  &&
    (lib.elemAt withClip.outputs 1).links == [
      2
      3
    ]
) "出力リンクが引数どおりに設定されていません";
# clipLink省略時もスロット自体は同じ並びで残し、リンクだけ未接続にする。
assert lib.assertMsg (
  slotNames withoutClip.inputs == slotNames withClip.inputs
) "clipLink省略時に入力スロットの並びが変わりました";
assert lib.assertMsg (
  (lib.elemAt withoutClip.inputs 2).link == null && (lib.elemAt withoutClip.outputs 1).links == [ ]
) "clipLink省略時にCLIPが未接続になっていません";
assert lib.assertMsg (withoutClip.title == "LoRA(high noise用)") "titleが反映されていません";
assert lib.assertMsg (!(withClip ? title)) "title未指定なのにtitleが付いています";
# mkNodeのオプション属性は省略時に属性ごと付かない。
# nullのまま出力するとComfyUIのJSONとして意味が変わり得る。
assert lib.assertMsg (
  !(plainNode ? widgets_values) && !(plainNode ? title)
) "省略したオプション属性が素のノードに付いています";
assert lib.assertMsg (
  plainNode.properties."Node name for S&R" == "TestNode"
) "S&R用のノード型名が設定されていません";
# 共通部品は使用するIDの範囲をコメントで約束している。
# 範囲が変わると全ワークフローの番号の振り方に影響するため固定する。
assert lib.assertMsg (
  promptWorkflow.last_node_id == 16 && promptWorkflow.last_link_id == 29
) "共通部品の最大ノードID・リンクIDが想定と違います";
assert lib.assertMsg (promptWorkflow.extra == { }) "app未指定の時にextraが空になっていません";
# 共通部品自体が各検証を通ることの確認。
assert lib.assertMsg (duplicate.duplicateIdErrors promptWorkflow == [ ]) "共通部品のIDが重複しています";
assert lib.assertMsg (link.invalidReferences promptWorkflow == [ ]) "共通部品のリンクが不整合です";
assert lib.assertMsg (order.orderErrors promptWorkflow == [ ]) "共通部品のorderが不整合です";
assert lib.assertMsg (overlap.overlappingNodePairs promptWorkflow.nodes == [ ]) "共通部品のノードが重なっています";
assert lib.assertMsg (lib.all (
  node: node.id != 4
) img2imgNodes) "withEmptyLatent = falseなのにEmptyLatentImageが生成されています";
assert lib.assertMsg (img2imgSampler.order == 7) "samplerOrderがKSamplerへ反映されていません";
# denoise 1未満はKSamplerAdvancedになり、
# 強さは実行ステップ数と連動する`start_at_step`として表される。
assert lib.assertMsg (
  img2imgSampler.type == "KSamplerAdvanced"
) "denoise 1未満なのにKSamplerAdvancedになっていません";
assert lib.assertMsg (
  img2imgSampler.widgets_values == [
    "enable"
    0
    "randomize"
    28
    5.5
    "euler_ancestral"
    "normal"
    14
    10000
    "disable"
  ]
) "denoiseがstart_at_stepへ変換されていません";
assert lib.assertMsg (
  (findNode (builder.promptNodes { }) 5).type == "KSampler"
) "denoise 1なのにKSamplerになっていません";
# `基準のsteps * denoise`がちょうど0.5になる組み合わせ。
# 切り捨てなので常に小さい側へ倒れ、doubleの表現誤差に結果が左右されない。
assert lib.assertMsg (
  builder.stepsForDenoise 30 0.35 == 10
  && builder.stepsForDenoise 30 0.55 == 16
  && builder.stepsForDenoise 30 0.75 == 22
) "0.5の境界に乗るdenoiseの丸めが切り捨てになっていません";
# 各ワークフローが実際に使っている組み合わせ。
# ここが変わると生成されるステップ数が黙って変わる。
assert lib.assertMsg (
  builder.stepsForDenoise builder.baseSteps 0.45 == 12
  && builder.stepsForDenoise builder.baseSteps 0.5 == 14
  && builder.stepsForDenoise builder.animaBaseSteps 0.3 == 9
) "実際に使っているdenoiseのステップ数が想定と違います";
assert lib.assertMsg (
  builder.startStepForDenoise builder.baseSteps 0.5 == 14
  && builder.startStepForDenoise builder.animaBaseSteps 0.5 == 15
) "実際に使っているdenoiseのstart_at_stepが想定と違います";
assert lib.assertMsg (
  builder.stepsForDenoise builder.baseSteps 1 == builder.baseSteps
) "denoise 1なのに基準のステップ数と違います";
# どのワークフローも通らない下限のクランプ。
# 検証がなければ壊れても気付けない。
assert lib.assertMsg (builder.stepsForDenoise builder.baseSteps 0.01 == 1) "ステップ数が1未満へ落ちています";
assert lib.assertMsg (
  outputLinks extraNodes 16 0 == [
    1
    90
  ]
  &&
    outputLinks extraNodes 16 1 == [
      2
      3
      91
    ]
) "MODEL・CLIPの追加リンクがLoraLoaderへ反映されていません";
assert lib.assertMsg (
  outputLinks extraNodes 1 2 == [
    8
    92
  ]
) "VAEの追加リンクがCheckpointLoaderへ反映されていません";
assert lib.assertMsg (
  outputLinks extraNodes 2 0 == [
    4
    93
  ]
  &&
    outputLinks extraNodes 3 0 == [
      5
      94
    ]
) "CONDITIONINGの追加リンクがCLIPTextEncodeへ反映されていません";
# filename_prefixの置換パターンはサーバ側のfolder_pathsの仕様に合わせている。
assert lib.assertMsg (
  builder.mkFilenamePrefix "test" == "test/test-%year%-%month%-%day%-%hour%-%minute%-%second%"
) "filename_prefixの形式が想定と違います";
assert lib.assertMsg (
  builder.mkFilenamePrefixWith "test" "-x"
  == "test/test-x-%year%-%month%-%day%-%hour%-%minute%-%second%"
) "サフィックス付きfilename_prefixの形式が想定と違います";
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
