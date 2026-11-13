# `lib/comfyui-api-workflow.nix`のテストが共有する入力と呼び出し方。
#
# この検査はbullet側の`comfyui/workflow/validate.nix`にあたるもので、
# あちらの検査ロジックが`test/eval/comfyui-workflow/link.nix`のような対のテストで守られているのに対し、
# こちらは「実際のワークフローで一度通した」だけだった。
# 検査が緩んでも、緩んだこと自体は誰も検出できない状態になる。
# 正常なワークフローを拒否せず、壊れたワークフローを見逃さないことを、
# 検査項目ごとのファイルで確かめる。
{ lib }:
rec {
  inherit (import ../../../lib/comfyui-api-workflow.nix { inherit lib; }) checks assertions;

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

  # 2つ目のサンプラー。
  # `seed`のように1つの入力を複数のノードへ配る形を再現するために置く。
  # 実際の`image-generation.nix`は`seed`を`[ "7" "14" "17" ]`の3つへ、
  # `image-edit.nix`は`image`を`[ "4" "17" "18" ]`の3つへ配っている。
  multiNodeWorkflow = lib.recursiveUpdate validWorkflow {
    "4" = {
      class_type = "KSampler";
      inputs = {
        seed = 0;
        model = [
          "2"
          0
        ];
      };
    };
    "3".inputs.images = [
      "4"
      0
    ];
  };

  multiNodes = [
    {
      type = "model";
      key = "unet_name";
      node_ids = [ "1" ];
    }
    {
      type = "seed";
      key = "seed";
      node_ids = [
        "2"
        "4"
      ];
    }
  ];

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

  # 呼び出し側が実際に使うのは`assertions`の方なので、そちらも通す。
  runAssertions =
    {
      workflow ? validWorkflow,
      workflowNodes ? validNodes,
      types ? validTypes,
      required ? requiredTypes,
    }:
    assertions {
      name = "テスト";
      inherit workflow workflowNodes;
      validTypes = types;
      requiredTypes = required;
    };

  failed = entries: lib.filter (entry: !entry.assertion) entries;
}
