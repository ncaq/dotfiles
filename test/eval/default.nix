/**
  評価時にしか走らない純粋なNixのテストを、ファイルごとに`checks`のderivationへ包む。

  型: { lib, runCommand } -> AttrSet Derivation

  何を集めるか:
    このディレクトリ以下の`.nix`ファイルを再帰的に集めて、1ファイルを1つのテストにする。
    どの階層でも、`default.nix`と`fixture.nix`という名前のファイルはテストとして扱わない。
    `default.nix`はこのファイル自身のため、
    `fixture.nix`はテスト間で共有する入力を置くための名前である。
    テストは`{ lib }`を受け取り、全ての表明を通ると`true`を返す。
    ファイルを足すだけでテストに加わる。

  属性名:
    `nix-test-`に、このディレクトリからの相対パスの拡張子を除いて`/`を`-`へ置き換えたものを付ける。
    例えば`comfyui-api-workflow/link.nix`は`nix-test-comfyui-api-workflow-link`になる。

  なぜ`checks`へ載せるか:
    検査される関数を使う側はホストの構成の中にあるので、
    そのホストを評価しない限りテストが走らない。
    CIで必ず走らせたい。

  なぜファイルごとにderivationを分けるか:
    `nix-fast-build`は`checks`の属性ごとに評価のワーカーへ割り振るので、
    分けておくと評価が並列に進む。
    落ちた時にどのトピックのテストかが属性名で分かる。
*/
{ lib, runCommand }:
let
  isTest =
    path:
    lib.hasSuffix ".nix" (toString path)
    && !(lib.elem (baseNameOf path) [
      "default.nix"
      "fixture.nix"
    ]);

  nameOf =
    path:
    "nix-test-"
    + lib.replaceStrings [ "/" ] [ "-" ] (
      lib.removeSuffix ".nix" (lib.removePrefix "./" (lib.path.removePrefix ./. path))
    );

  # `builtins.seq`でテストの値を強制してからビルドを成功させる。
  # 強制はderivationのinstantiation時にだけ起きるので、
  # `nix flake show`のように属性へ触れるだけのコマンドではテストは走らない。
  mkNixTest =
    path:
    let
      name = nameOf path;
      test = import path { inherit lib; };
    in
    lib.nameValuePair name (
      runCommand name {
        passed = builtins.seq (
          assert test;
          test
        ) name;
      } ''echo "$passed" > "$out"''
    );

  tests = map mkNixTest (lib.filter isTest (lib.filesystem.listFilesRecursive ./.));

  # `/`を`-`へ置き換えるので、`a/b-c.nix`と`a-b/c.nix`のような別のファイルが同じ名前になり得る。
  # `lib.listToAttrs`は重複した名前の片方を黙って捨てるので、
  # テストが`checks`から消えたことに気付けるように評価を止める。
  names = map (test: test.name) tests;
  duplicateNames = lib.unique (lib.filter (name: lib.count (other: other == name) names > 1) names);
in
assert lib.assertMsg (
  duplicateNames == [ ]
) "テストの属性名が衝突しています: ${lib.concatStringsSep ", " duplicateNames}";
lib.listToAttrs tests
