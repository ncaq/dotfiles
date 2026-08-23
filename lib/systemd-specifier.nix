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
  specifier = import ../../../../lib/systemd-specifier.nix { inherit lib; };
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
in
{
  inherit hasUnsafeSpecifier;

  /**
    属性集合のうち、値が壊れているものの名前。

    型: AttrsOf String -> [ String ]
  */
  unsafeNames = attrs: lib.attrNames (lib.filterAttrs (_: hasUnsafeSpecifier) attrs);
}
