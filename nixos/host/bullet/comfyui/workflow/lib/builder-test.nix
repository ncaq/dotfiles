# `mkLoraLoader`が生成するノードの形状を検証する。
#
# `Lora Loader (LoraManager)`は入力スロットの並びとウィジェットの並びが、
# LoRA Manager側のノード定義と一致していないと、
# 管理画面のSend to Workflowがこのノードを見つけられず動かなくなる。
# 他のassertionはリンクやorderしか見ないため、
# 綴りや並びが崩れてもビルドは通ってUIで開くまで気付けない。
{ lib }:
let
  builder = import ./builder.nix { inherit lib; };
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
true
