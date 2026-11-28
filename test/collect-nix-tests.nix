/**
  モジュールの隣に置いたテストを、ファイルごとに`checks`のderivationにする。
  評価時にしか走らない純粋なNixのテストと、
  モジュールだけを読み込んだマシンで実際に動かすNixOS Testの2種類がある。

  型: { lib, localLib, runCommand, testers } -> AttrSet Derivation

  何を集めるか:
    リポジトリの中の、名前が`.test.nix`で終わるファイルを再帰的に集めて、1ファイルを1つのテストにする。
    テストは実装のファイルの末尾に`assert`として直接書くのが基本で、
    ここで集めるのは、
    モジュール自身を`lib.evalModules`で読み込むので自分のファイルの中には書けないテスト。
    確かめる実装の隣に置き、`<実装の名前>.test.nix`という名前にする。
    トピックを分ける時は`<実装の名前>.<トピック>.test.nix`にする。
    テストは`{ lib }`を受け取り、全ての表明を通ると`true`を返す。
    `lib/`の定義を使うテストは`{ lib, localLib }`のように`localLib`も受け取れる。
    ファイルを足すだけでテストに加わる。

    同じ名前の付け方で、`{ testers }`か`{ lib, testers }`を受け取って`testers.runNixOSTest`のderivationを返すテストも集める。
    コマンドを持たないモジュールの振る舞いを、ホストをブートせずに確かめるためのもの。
    コマンドを持つものは、パッケージのテスト(`pkgs/<名前>/nixos-test.nix`)に書く。

    モジュールのディレクトリに置いても、
    `importDirModules`が`.test.nix`をモジュールとして読まないので混ざらない。

  属性名:
    `nix-test-`に、リポジトリのルートからの相対パスの`.test.nix`を除いて、
    `/`と`.`を`-`へ置き換えたものを付ける。
    例えば`nixos/native-linux/networking.container-dns.test.nix`は、
    `nix-test-nixos-native-linux-networking-container-dns`になる。

  なぜ`checks`へ載せるか:
    実装のファイルから読み込まれないテストは、
    どこかから評価しない限り走らない。
    CIで必ず走らせたい。

  なぜファイルごとにderivationを分けるか:
    `nix-fast-build`は`checks`の属性ごとに評価のワーカへ割り振るので、
    分けておくと評価が並列に進む。
    落ちた時にどのトピックのテストかが属性名で分かる。
*/
{
  lib,
  localLib,
  runCommand,
  testers,
}:
let
  root = ../.;

  suffix = ".test.nix";

  isTest = path: lib.hasSuffix suffix (toString path);

  nameOf =
    path:
    "nix-test-"
    + lib.replaceStrings [ "/" "." ] [ "-" "-" ] (
      lib.removeSuffix suffix (lib.removePrefix "./" (lib.path.removePrefix root path))
    );

  # `builtins.seq`でテストの値を強制してからビルドを成功させる。
  # 強制はderivationのinstantiation時にだけ起きるので、
  # `nix flake show`のように属性へ触れるだけのコマンドではテストは走らない。
  #
  # `testers`を受け取るテストは、モジュールを実際に動かすNixOS Testで、
  # 返したderivationをそのまま載せる。
  # どちらの形かは関数の引数で見分けるので、見分けるためにテストの値を強制することはない。
  mkNixTest =
    path:
    let
      name = nameOf path;
      test = import path;
    in
    lib.nameValuePair name (
      if lib.functionArgs test ? testers then
        # `lib`を使わないテストが受け取らずに済むように、求められた引数だけを渡す。
        test (builtins.intersectAttrs (lib.functionArgs test) { inherit lib localLib testers; })
      else
        let
          result = test (builtins.intersectAttrs (lib.functionArgs test) { inherit lib localLib; });
        in
        runCommand name {
          passed = builtins.seq (
            assert result;
            result
          ) name;
        } ''echo "$passed" > "$out"''
    );

  tests = map mkNixTest (lib.filter isTest (lib.filesystem.listFilesRecursive root));

  # `/`と`.`を`-`へ置き換えるので、`a/b-c.test.nix`と`a-b/c.test.nix`のような別のファイルが同じ名前になり得る。
  # `lib.listToAttrs`は重複した名前の片方を黙って捨てるので、
  # テストが`checks`から消えたことに気付けるように評価を止める。
  names = map (test: test.name) tests;
  duplicateNames = lib.unique (lib.filter (name: lib.count (other: other == name) names > 1) names);
in
assert lib.assertMsg (
  duplicateNames == [ ]
) "テストの属性名が衝突しています: ${lib.concatStringsSep ", " duplicateNames}";
lib.listToAttrs tests
