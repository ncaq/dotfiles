# 呼び出し側が実際に使う`assertions`の側。
# `checks`だけを叩いていると、
# 検査を足して対応表への配線を忘れた場合にテストが通り続けてしまう。
{ lib }:
let
  inherit (import ./fixture.nix { inherit lib; })
    validWorkflow
    run
    runAssertions
    failed
    ;
in
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
