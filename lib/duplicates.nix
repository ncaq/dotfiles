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

  # 以下は末尾の`assert`のための入力。
  entry = name: value: { inherit name value; };
  duplicated = findDuplicates [
    1
    2
    1
    3
    2
  ];
  onePair = formatDuplicates toString [
    (entry "a" 1)
    (entry "b" 2)
    (entry "c" 1)
  ];
  twoPairs = formatDuplicates toString [
    (entry "a" 1)
    (entry "b" 2)
    (entry "c" 1)
    (entry "d" 2)
  ];
  noPair = formatDuplicates toString [
    (entry "a" 1)
    (entry "b" 2)
  ];
in
assert lib.assertMsg (
  duplicated == [
    1
    2
  ]
) "2回以上現れる値を、最初に現れた順に1つずつ返しません: ${builtins.toJSON duplicated}";
assert lib.assertMsg (onePair == "1 (a, c)") "重複が1組の時の書き方が違います: ${onePair}";
assert lib.assertMsg (twoPairs == "1 (a, c); 2 (b, d)") "重複が2組の時の書き方が違います: ${twoPairs}";
assert lib.assertMsg (noPair == "") "重複が無い時に空文字列になりません: ${noPair}";
{
  inherit findDuplicates formatDuplicates;
}
