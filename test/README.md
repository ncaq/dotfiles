# test

Nixで書いたテストのうち、
実装のファイルに書けないものと、
テストを集める仕組みを置いています。
1つのファイルには1つのトピックだけを書きます。

- `collect-nix-tests.nix`: 実装のファイルに書けない評価のテスト(`*.test.nix`)を集める仕組み
- `nixos-boot/`: ホストごとにNixOSの構成をVMでブートするテスト(`testNixosBoot`)。
  `script/`はブート後に確かめるトピック、
  `vm/`はテストVMで動かないものを無効化したりモックにしたりするモジュール

各言語のパッケージのテスト(`pkgs/*/test`など)は、
その言語のツールが期待する場所に置いたままにします。

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

- `nixos/host/seminar/machine-mapping.nix`のテストは`nixos/host/seminar/machine-mapping.test.nix`
- トピックを分ける時は`nixos/native-linux/networking.container-dns.test.nix`のように`<実装の名前>.<トピック>.test.nix`
- `importDirModules`は`.test.nix`をモジュールとして読まない
