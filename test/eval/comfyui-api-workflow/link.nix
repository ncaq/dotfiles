# 接続(`[ノードID スロット番号]`)の検査が、
# 存在しないノードへの接続を見逃さず、接続でない値を接続と誤認しないこと。
{ lib }:
let
  inherit (import ./fixture.nix { inherit lib; }) validWorkflow run;
in
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
true
