# `lib/systemd-specifier.nix`の検査が、
# 壊れた値を見逃さず、正しい値を拒否しないことを確かめる。
#
# この検査は一度実際に踏んだ不具合への対策だが、
# 最初の実装は`lib.replaceStrings [ "%%" ] [ "" ]`の結果に`%`が残るかを見るもので、
# `%`が偶数個なら必ず空になるため過剰なエスケープを素通りさせていた。
# 手作業で一度確かめただけでは、
# 判定の穴も、後から判定を緩めてしまった場合も検出できない。
{ lib }:
let
  specifier = import ./systemd-specifier.nix { inherit lib; };
  inherit (specifier) hasUnsafeSpecifier unsafeNames;
in
assert lib.assertMsg (!(hasUnsafeSpecifier "plain-text")) "`%`を含まない値を拒否しました";
assert lib.assertMsg (!(hasUnsafeSpecifier "open-webui-%%year%%-%%month%%")) "正しく二重化された値を拒否しました";
assert lib.assertMsg (hasUnsafeSpecifier "open-webui-%year%") "specifierへ展開される`%`を見逃しました";
assert lib.assertMsg (hasUnsafeSpecifier "open-webui-%%%%year%%%%") "過剰にエスケープされた`%`を見逃しました";
# 3個の連続は先頭2つがリテラルになった後、残る1つが展開される。
assert lib.assertMsg (hasUnsafeSpecifier "a%%%b") "奇数個の連続を見逃しました";
# 末尾の`%`は次の文字が無くてもsystemdの解釈対象なので許さない。
assert lib.assertMsg (hasUnsafeSpecifier "trailing%") "末尾の単独の`%`を見逃しました";
# 1つの値の中に正しい二重化と壊れた指定が混ざる場合も拾う。
assert lib.assertMsg (hasUnsafeSpecifier "%%year%%-%month%") "混在した値の壊れた側を見逃しました";
assert lib.assertMsg (unsafeNames { } == [ ]) "空の属性集合から名前を報告しました";
assert lib.assertMsg (
  unsafeNames {
    GOOD = "%%year%%";
    ALSO_GOOD = "no percent";
  } == [ ]
) "正しい属性集合から名前を報告しました";
assert lib.assertMsg (
  unsafeNames {
    GOOD = "%%year%%";
    BROKEN = "%year%";
    EXCESSIVE = "%%%%year%%%%";
  } == [
    "BROKEN"
    "EXCESSIVE"
  ]
) "壊れた値の名前を正しく報告できませんでした";
true
