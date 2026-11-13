# `workflowNodes`の`type`がOpen WebUI側のフォームと食い違っていたら見逃さないこと。
{ lib }:
let
  inherit (import ./fixture.nix { inherit lib; }) validNodes requiredTypes run;
in
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

# `requiredTypes`が`validTypes`に無い`type`を要求している場合。
# 引数同士の矛盾なので、ワークフローの側をどう書いても通らない。
assert lib.assertMsg (
  (run {
    required = requiredTypes ++ [ "nonexistent_type" ];
  }).contradictoryTypes == [ "nonexistent_type" ]
) "引数同士の矛盾を見逃しました";
true
