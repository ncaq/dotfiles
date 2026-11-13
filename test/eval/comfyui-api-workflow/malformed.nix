# ノードとして必要な属性を書き忘れたノードを見逃さないこと。
{ lib }:
let
  inherit (import ./fixture.nix { inherit lib; }) validWorkflow run;
in
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
true
