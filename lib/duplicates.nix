/**
  割り当てた値の重複を探して、assertionのメッセージに使える形にする関数の組。

  # 引数

  - `lib`: リスト操作に使う

  # 返り値

  - `findDuplicates`: リストの中で2回以上現れる値のリスト
  - `formatDuplicates`: `{ name, value }`のリストから重複を探して、
    「値 (名前1, 名前2)」の形の文字列にする。
    最初の引数は値を文字列にする関数
*/
{ lib }:
let
  findDuplicates = list: lib.unique (lib.filter (x: lib.count (y: x == y) list > 1) list);
  formatDuplicates =
    toStr: entries:
    let
      namesForValue =
        dupVal: lib.concatMapStringsSep ", " (e: e.name) (lib.filter (e: e.value == dupVal) entries);
    in
    lib.concatMapStringsSep "; " (dupVal: "${toStr dupVal} (${namesForValue dupVal})") (
      findDuplicates (map (e: e.value) entries)
    );
in
assert
  findDuplicates [
    1
    2
    1
    3
    2
  ] == [
    1
    2
  ];
assert
  formatDuplicates toString [
    {
      name = "a";
      value = 1;
    }
    {
      name = "b";
      value = 2;
    }
    {
      name = "c";
      value = 1;
    }
  ] == "1 (a, c)";
{
  inherit findDuplicates formatDuplicates;
}
