# 出力ノードから辿れないノードを見逃さないこと。
{ lib }:
let
  inherit (import ./fixture.nix { inherit lib; }) validWorkflow run;
in
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
true
