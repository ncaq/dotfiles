# `lib/comfyui-api-workflow.nix`の検査が、
# 正常なワークフローを拒否せず、壊れたワークフローを見逃さないことを確かめる。
#
# この検査はbullet側の`comfyui/workflow/validate.nix`にあたるもので、
# あちらの検査ロジックが`link-test.nix`のような対のテストで守られているのに対し、
# こちらは「実際のワークフローで一度通した」だけだった。
# 検査が緩んでも、緩んだこと自体は誰も検出できない状態になる。
{ lib }:
let
  inherit (import ./comfyui-api-workflow.nix { inherit lib; }) checks assertions;

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

# 第1要素が文字列でない2要素リストも接続ではない。
# `lib.isString`のガードを外すと、
# ノードIDとして文字列補間しようとして読めない型エラーになる。
assert lib.assertMsg (
  (run {
    workflow = lib.recursiveUpdate validWorkflow {
      "1".inputs.unet_name = [
        0
        0
      ];
    };
  }).danglingLinks == [ ]
) "第1要素が文字列でない値を接続と誤認しました";

# スロット番号を文字列で書き間違えた場合。
#
# 接続とみなさないので`danglingLinks`には出ないが、
# その分だけ依存が辿れなくなって参照先が経路から外れる。
# `isLink`が第2要素の整数性を見る意味は、
# 書き間違いをこの経路で捕まえることにある。
assert lib.assertMsg (
  (run {
    workflow = lib.recursiveUpdate validWorkflow {
      "2".inputs.model = [
        "1"
        "0"
      ];
    };
  }).orphanNodes == [ "1" ]
) "スロット番号の書き間違いが到達性の側で捕まりませんでした";

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

# 同じ`type`を2行書いた場合も、報告は1度だけにする。
assert lib.assertMsg (
  (run {
    workflowNodes = validNodes ++ [
      {
        type = "negative_prompt";
        key = "seed";
        node_ids = [ "2" ];
      }
      {
        type = "negative_prompt";
        key = "seed";
        node_ids = [ "2" ];
      }
    ];
  }).unknownTypes == [ "negative_prompt" ]
) "フォームに無いtypeを重複して報告しました";

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

# `node_ids`が複数ある場合に、2番目以降も見ていること。
#
# 実際のワークフローは`seed`も`image`も複数のノードへ配るので、
# `lib.head entry.node_ids`のように先頭だけを見る実装へ退化すると、
# production側の主要な形が丸ごと検査されなくなる。
assert lib.assertMsg (allEmpty (run {
  workflow = multiNodeWorkflow;
  workflowNodes = multiNodes;
})) "複数のnode_idsを持つ正常なワークフローを拒否しました";

assert lib.assertMsg (
  (run {
    workflow = multiNodeWorkflow;
    workflowNodes = [
      {
        type = "seed";
        key = "seed";
        node_ids = [
          "2"
          "97"
        ];
      }
    ];
  }).missingNodes == [ "seed -> 97" ]
) "node_idsの2番目が存在しないことを見逃しました";

assert lib.assertMsg (
  (run {
    # `1`はUNETLoaderで`seed`を持たない。
    workflow = multiNodeWorkflow;
    workflowNodes = [
      {
        type = "seed";
        key = "seed";
        node_ids = [
          "2"
          "1"
        ];
      }
    ];
  }).missingKeys == [ "seed -> 1.seed" ]
) "node_idsの2番目だけがkeyを持たないことを見逃しました";

# `requiredTypes`が`validTypes`に無い`type`を要求している場合。
# 引数同士の矛盾なので、ワークフローの側をどう書いても通らない。
assert lib.assertMsg (
  (run {
    required = requiredTypes ++ [ "nonexistent_type" ];
  }).contradictoryTypes == [ "nonexistent_type" ]
) "引数同士の矛盾を見逃しました";

# ここから`assertions`の側。
# `checks`だけを叩いていると、
# 検査を足して対応表への配線を忘れた場合にテストが通り続けてしまう。
assert lib.assertMsg (failed (runAssertions { }) == [ ]) "正常なワークフローでassertionが落ちました";

# 全ての検査項目がassertionへ配線されていること。
#
# 数の一致だけでは足りない。
# `assertions`は`checks`の結果の側を走査するので、
# 対応表に無い項目があっても数は必ず一致する。
# `message`は`assertion`が真の間は評価されないため、
# ここで文字列として強制して初めて`missing attribute`が出る。
assert lib.assertMsg (
  lib.length (runAssertions { }) == lib.length (lib.attrNames (run { }))
) "checksの項目数とassertionsの数が一致しません";
assert lib.assertMsg (lib.all (entry: lib.isString entry.message) (
  runAssertions { }
)) "assertionのメッセージを組み立てられませんでした";

# 壊した時にメッセージへ壊した箇所が載ること。
#
# 接続先を存在しないIDにすると、
# そのノードが経路から外れるので到達性の側でも落ちる。
# 件数は決め打ちにせず、
# 接続の項目が壊した先を名指ししていることだけを見る。
assert lib.assertMsg (
  let
    broken = failed (runAssertions {
      workflow = lib.recursiveUpdate validWorkflow {
        "3".inputs.images = [
          "99"
          0
        ];
      };
    });
  in
  lib.any (entry: lib.hasInfix "3.images -> 99" entry.message) broken
) "assertionのメッセージに壊した接続先が載りませんでした";
true
