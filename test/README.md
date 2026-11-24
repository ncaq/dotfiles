# test

Nixで書いたテストのうち、
実装のファイルに書けないものと、
テストを集める仕組みを置いています。
1つのファイルには1つのトピックだけを書きます。

- `collect-nix-tests.nix`: 実装の隣に置いたテスト(`*.test.nix`)を集める仕組み。
  実装のファイルに書けない評価のテストと、モジュールだけを動かすNixOS Testを集める
- `nixos-boot/`: ホストごとにNixOSの構成をVMでブートするテスト(`testNixosBoot`)。
  `script/`はブート後に確かめるトピック、
  `vm/`はテストVMで動かないものを無効化したりモックにしたりするモジュール

各言語のパッケージのテスト(`pkgs/*/test`など)は、
その言語のツールが期待する場所に置いたままにします。

## ブートテストに書くものとパッケージのテストに書くもの

ホストの構成に依らずに確かめられる振る舞いは、
`nixos-boot/`ではなく、
確かめるモジュールだけを読み込んだマシンで動かすNixOS Testに書きます。
マシンはsystemd-nspawnのコンテナにします。
ホストをブートしないので数秒で終わり、
ブートテストでは起こせない状態(GCが動いている最中など)も作れます。

- コマンドを持つものは、パッケージのテスト(`pkgs/<名前>/nixos-test.nix`)。
  コマンドとそれを動かすユニットを`pkgs/<名前>`に揃えます。
  書き方は`pkgs/README.md`に書いています
- コマンドを持たないモジュールは、モジュールの隣の`.test.nix`。
  `nixos/core/caddy.test.nix`のように、
  `{ testers }`を受け取って`testers.runNixOSTest`のderivationを返します。
  下の評価のテストと同じく`collect-nix-tests.nix`が集めます

`nixos-boot/`に書くのは、実機の構成を組み上げた結果を見るものだけです。

- 実機のルールセットやユニットの並びのように、複数のモジュールの合成で決まるもの
- 実機のコンテナやmicroVMを実際に起動して確かめるもの
- パッケージのテストで見た振る舞いが、実機の置き場所や名前で繋がっていること

## 実装のファイルに書くテスト

評価時にしか走らない純粋なNixのテストは、
実装のファイルの末尾に`assert`としてそのまま書きます。
`lib/parse-ipv6.nix`のように、
実装を`let`で束縛して、
`assert`を並べた後に実装を返します。
ファイルを読み込むたびに表明が走るので、
使っているホストの評価がそのままテストになります。
`lib`を受け取らないファイルでは`assert 条件 || throw "メッセージ";`と書きます。

トピックが複数ある時は、
`lib/comfyui-api-workflow.nix`のように、
トピックごとの`let ... in assert ...; true`を`tests`の属性として並べて、
まとめて`assert`します。
トピックごとに束縛の名前が分かれるので、
入力の名前が重なりません。

## `.test.nix`に分けるテスト

実装のファイルに書けないのは、
モジュール自身を`lib.evalModules`で読み込むテストだけです。
モジュールのファイルの中に書くと、
テストが読み込んだ自分自身の中でまたテストが走って無限再帰になります。
そのテストは隣に`.test.nix`で終わる名前のファイルとして置きます。
リポジトリのどこに置いても`collect-nix-tests.nix`が集めて、
1ファイルが`checks`の1つの`nix-test-*`になります。

- `nixos/native-linux/machine-mapping.nix`のテストは`nixos/native-linux/machine-mapping.test.nix`
- トピックを分ける時は`nixos/native-linux/networking.container-dns.test.nix`のように`<実装の名前>.<トピック>.test.nix`
- `importDirModules`は`.test.nix`をモジュールとして読まない
