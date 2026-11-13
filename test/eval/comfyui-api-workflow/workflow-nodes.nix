# `workflowNodes`がワークフローに無いノードや入力を指していたら見逃さないこと。
{ lib }:
let
  inherit (import ./fixture.nix { inherit lib; })
    validNodes
    multiNodeWorkflow
    multiNodes
    run
    allEmpty
    ;
in
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
true
