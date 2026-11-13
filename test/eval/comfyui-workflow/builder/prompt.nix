# 全ワークフローの土台である`builder.promptNodes`と`builder.promptLinks`を検証する。
#
# 引数がノードへ反映されることと、
# 呼び出し元が最低限の後続ノードを足した状態で、
# ID重複・リンク・order・重なりの各検証を通ることを確かめる。
{ lib }:
let
  inherit (import ../fixture.nix { inherit lib; })
    builder
    duplicate
    link
    order
    overlap
    ;

  findNode = nodes: id: lib.findFirst (node: node.id == id) null nodes;
  outputLinks =
    nodes: id: slot:
    (lib.elemAt (findNode nodes id).outputs slot).links;

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

  # 追加リンクは共通ノードの出力の既定リンクの後ろへ足される。
  extraNodes = builder.promptNodes {
    extraModelLinks = [ 90 ];
    extraClipLinks = [ 91 ];
    extraVaeLinks = [ 92 ];
    extraPositiveLinks = [ 93 ];
    extraNegativeLinks = [ 94 ];
  };
in
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
assert lib.assertMsg ((findNode img2imgNodes 5).order == 7) "samplerOrderがKSamplerへ反映されていません";
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
true
