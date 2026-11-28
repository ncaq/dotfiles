/**
  systemdのユニットへ渡す値が、
  specifierとして展開されて壊れないかを検査する関数。

  `Environment=`や`ExecStart=`に載る値の中の`%`は、
  次の1文字と組にしてsystemdが展開する。
  `%y`はユニットファイルのパスへ、
  `%m`はマシンIDへ、
  `%s`はシェルのパスへ変わる。
  リテラルの`%`を渡すには`%%`と二重にする必要がある。

  厄介なのは、
  展開されても文字列としては成立してしまうため、
  ユニットは何の警告も出さずに起動することである。
  Open WebUIの画像生成では`filename_prefix`に書いた`%year%`がこれで壊れて、
  出力されたファイル名を見るまで気付けなかった。

  # 判定

  `%`の極大連続の長さが2以外なら壊れているとみなす。

  1個ならsystemdがspecifierとして展開する。
  3個以上も同じで、
  先頭の2つがリテラルの`%`になった後、残りが展開される。

  4個以上の偶数はsystemdを通っても壊れないが、
  `%%%%year%%%%`は展開後に`%%year%%`が残るため、
  `%year%`の形しか置換しないComfyUIの`get_save_image_path`と噛み合わない。
  出力されたファイル名を見るまで気付けないという点で同じ壊れ方なので、
  こちらも弾く。

  ```nix
  specifier = import ./lib/systemd-specifier.nix { inherit lib; };
  broken = specifier.unsafeNames config.local.openWebui.environment;
  ```
*/
{ lib }:
let
  /**
    値がsystemdのspecifierとして展開される`%`を含むかどうか。

    型: String -> Bool
  */
  hasUnsafeSpecifier =
    value:
    let
      # `builtins.split`はキャプチャグループをリストとして返し、
      # 一致しなかった部分は文字列のまま残る。
      # 括弧で囲まないと空リストしか返らず、連続の長さを数えられない。
      runs = lib.filter lib.isList (builtins.split "(%+)" value);
    in
    lib.any (run: lib.stringLength (lib.head run) != 2) runs;

  /**
    属性集合のうち、値が壊れているものの名前。

    型: AttrsOf String -> [ String ]
  */
  unsafeNames = attrs: lib.attrNames (lib.filterAttrs (_: hasUnsafeSpecifier) attrs);
in
# 壊れた値を見逃さず、正しい値を拒否しないことを確かめる。
#
# この検査は一度実際に踏んだ不具合への対策だが、
# 最初の実装は`lib.replaceStrings [ "%%" ] [ "" ]`の結果に`%`が残るかを見るもので、
# `%`が偶数個なら必ず空になるため過剰なエスケープを素通りさせていた。
# 手作業で一度確かめただけでは、
# 判定の穴も、後から判定を緩めてしまった場合も検出できない。
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
{
  inherit hasUnsafeSpecifier unsafeNames;
}
