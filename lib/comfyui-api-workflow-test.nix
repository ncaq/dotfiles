# `lib/comfyui-api-workflow.nix`の検査が、
# 正常なワークフローを拒否せず、壊れたワークフローを見逃さないことを確かめる。
#
# この検査はbullet側の`comfyui/workflow/lib/validate.nix`にあたるもので、
# あちらの検査ロジックが`link-test.nix`のような対のテストで守られているのに対し、
# こちらは「実際のワークフローで一度通した」だけだった。
# 検査が緩んでも、緩んだこと自体は誰も検出できない状態になる。
{ lib }:
let
  inherit (import ./comfyui-api-workflow.nix { inherit lib; }) checks;

  # 実際のワークフローの構造を最小限に写したもの。
  # ローダーからサンプラーを経て保存ノードへ至る、という骨格は同じにする。
  validWorkflow = {
    "1" = {
      class_type = "UNETLoader";
      inputs.unet_name = "example.safetensors";
    };
    "2" = {
      class_type = "KSampler";
      inputs = {
        seed = 0;
        model = [
          "1"
          0
        ];
      };
    };
    "3" = {
      class_type = "SaveImage";
      inputs = {
        filename_prefix = "example";
        images = [
          "2"
          0
        ];
      };
    };
  };

  validNodes = [
    {
      type = "model";
      key = "unet_name";
      node_ids = [ "1" ];
    }
    {
      type = "seed";
      key = "seed";
      node_ids = [ "2" ];
    }
  ];

  validTypes = [
    "model"
    "seed"
  ];
  requiredTypes = [ "model" ];

  run =
    {
      workflow ? validWorkflow,
      workflowNodes ? validNodes,
      types ? validTypes,
      required ? requiredTypes,
    }:
    checks {
      inherit workflow workflowNodes;
      validTypes = types;
      requiredTypes = required;
    };

  # 全ての検査項目が空であること。
  allEmpty = result: lib.all (items: items == [ ]) (lib.attrValues result);
in
assert lib.assertMsg (allEmpty (run { })) "正常なワークフローを拒否しました";

# 接続先のIDを打ち間違えた場合。
assert lib.assertMsg (
  (run {
    workflow = lib.recursiveUpdate validWorkflow {
      "3".inputs.images = [
        "99"
        0
      ];
    };
  }).danglingLinks != [ ]
) "存在しないノードへの接続を見逃しました";

# ウィジェットの値が接続と同じ形をしていても接続とみなさないこと。
# スロット番号が整数でないので接続ではない。
assert lib.assertMsg (
  (run {
    workflow = lib.recursiveUpdate validWorkflow {
      "1".inputs.unet_name = [
        "a"
        "b"
      ];
    };
  }).danglingLinks == [ ]
) "第2要素が整数でない値を接続と誤認しました";

# 3要素のリストも接続ではない。
assert lib.assertMsg (
  (run {
    workflow = lib.recursiveUpdate validWorkflow {
      "1".inputs.unet_name = [
        "a"
        0
        1
      ];
    };
  }).danglingLinks == [ ]
) "3要素のリストを接続と誤認しました";

# 保存ノードの入力を戻してしまい、間のノードが経路から外れた場合。
assert lib.assertMsg (
  (run {
    workflow = lib.recursiveUpdate validWorkflow {
      "3".inputs.images = [
        "1"
        0
      ];
    };
  }).orphanNodes == [ "2" ]
) "出力ノードから到達できないノードを見逃しました";

# `inputs`を書き忘れたノード。
assert lib.assertMsg (
  (run {
    workflow = validWorkflow // {
      "4".class_type = "PreviewImage";
    };
  }).malformedNodes == [ "4" ]
) "inputsを持たないノードを見逃しました";

# `class_type`を書き忘れたノード。
assert lib.assertMsg (
  (run {
    workflow = validWorkflow // {
      "4".inputs = { };
    };
  }).malformedNodes == [ "4" ]
) "class_typeを持たないノードを見逃しました";

# `workflowNodes`が存在しないノードを指す場合。
assert lib.assertMsg (
  (run {
    workflowNodes = validNodes ++ [
      {
        type = "seed";
        key = "seed";
        node_ids = [ "98" ];
      }
    ];
  }).missingNodes != [ ]
) "workflowNodesの存在しないノードを見逃しました";

# `key`が対象ノードに無い場合。
assert lib.assertMsg (
  (run {
    workflowNodes = [
      {
        type = "model";
        key = "nonexistent";
        node_ids = [ "1" ];
      }
    ];
  }).missingKeys != [ ]
) "対象ノードが持たない入力を見逃しました";

# Open WebUI側のフォームに無い`type`を書いた場合。
# このPRで踏んだ`negative_prompt`と`steps`がこの形だった。
assert lib.assertMsg (
  (run {
    workflowNodes = validNodes ++ [
      {
        type = "negative_prompt";
        key = "seed";
        node_ids = [ "2" ];
      }
    ];
  }).unknownTypes == [ "negative_prompt" ]
) "フォームに無いtypeを見逃しました";

# 必要な`type`の行を消した場合。
assert lib.assertMsg (
  (run {
    workflowNodes = lib.filter (entry: entry.type != "model") validNodes;
  }).absentTypes == [ "model" ]
) "必要なtypeの欠落を見逃しました";

# 同じ`type`を2度書いた場合。
assert lib.assertMsg (
  (run {
    workflowNodes = validNodes ++ [
      {
        type = "seed";
        key = "seed";
        node_ids = [ "2" ];
      }
    ];
  }).duplicateTypes == [ "seed" ]
) "重複したtypeを見逃しました";
true
