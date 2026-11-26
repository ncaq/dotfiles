# pkgs

自作のパッケージです。
`lib/local-packages-overlay.nix`が`lib.packagesFromDirectoryRecursive`で走査して、
全環境で共通のoverlayとしてnixpkgsのトップレベルに生やします。

`pkgs/<名前>.nix`か`pkgs/<名前>/package.nix`を置くだけで、
モジュールからは`pkgs.<名前>`として使え、
flakeの`packages`と`checks`にも加わります。
`flake.nix`やモジュールでパスを指定して`callPackage`する必要はありません。
ホストの設定に合わせた引数を渡したい時は`pkgs.<名前>.override`を使います。

`niks3`のようなnixpkgsに無いflakeのinputは、
overlayが`callPackage`の自動で渡す引数に足しています。
`home-manager`のように、
nixpkgsにあってもinputと版を揃えたいものも同じように足しています。
`homeManagerConfiguration`のように、
パッケージではなくテストがhome-managerのモジュールを評価するための関数も足しています。

Haskellのパッケージは、
overlayが渡す`localHaskellPackages`の`callCabal2nix`で組みます。
nixpkgsの`haskellPackages`にhimariを足したパッケージセットで、
全ての自作パッケージが同じものを共有します。
パッケージごとに`haskellPackages.extend`すると、
himariとその依存をパッケージの数だけ評価し直すことになります。

新しく書く時の言語の選び方は`docs/helper-program-language-policy.md`に書いてあります。

## テスト

パッケージの`passthru.tests`に置いたderivationも、
`checks`の`local-package-tests`へ`<名前>-test-<テストの名前>`として束ねられて確かめられます。
`comfyui-ncaq-nodes`のように、
テストを書き換えただけで配るもののstoreパスが変わると困る時に、
`checkPhase`の代わりに使います。

各言語のテストは、
その言語のツールが期待する場所(`<名前>/test`など)に置きます。

### ユニットごと確かめるテスト

プログラムがsystemdのユニットとの組み合わせで意味を持つ時は、
ユニットを定義するNixOSモジュールもパッケージの隣に置いて、
NixOS Testで実際のユニットを動かします。
ここで言うプログラムはコマンドに限らず、
`gpg-vault`のようにユニットが動かすデーモンへ渡す設定ファイルをまとめたものも含みます。

- `<名前>/package.nix`: プログラム。`passthru.tests.nixos`に`nixos-test.nix`を置く
- `<名前>/module.nix`: プログラムを動かすユニットのNixOSモジュール。
  ホストの構成に依存させず、置き場所のようなホストごとの値はオプションで受け取る
- `<名前>/nixos-test.nix`: `module.nix`だけを読み込んだマシンで確かめるテスト

ホストの側は、`nixos/core/trash.nix`のように`module.nix`を`imports`に書いて使います。
`importDirModules`は`pkgs/`を走査しないので、ここだけは明示的に読み込みます。

`gpg-vault`のようにユーザの側の設定と組になるものは、
home-managerのモジュールも`<名前>/home-module.nix`として隣に置いて、
`home/core/gpg.nix`のように`imports`に書いて使います。
`home-module.nix`も`nixos-test.nix`の中で確かめます。
overlayが渡す`homeManagerConfiguration`で評価して、
出てきたファイルをテストのマシンへ置きます。
home-managerの有効化そのものはコンテナの中で動かせないためで、
書き方は`pkgs/gpg-vault/nixos-test.nix`の冒頭に書いています。

モジュールが入力に掛けている型やassertionは、
`<名前>/module.test.nix`に評価のテストとして書けます。
`package.nix`のあるディレクトリでもパッケージとしては拾われず、
`test/README.md`に書いている仕組みが`checks`へ集めます。

テストのマシンは、`nodes`ではなく`containers`に書いて、
QEMUのVMではなくsystemd-nspawnのコンテナで動かします。
ホストをブートしないので数秒で終わります。
カーネルや起動の過程に関わるものを確かめる時だけ`nodes`にします。
コンテナのテストを実行するnix-daemonに要る設定は、
`nixos/core/nix-daemon.nix`に書いています。

## 制約

置くだけで拾われる裏返しとして、
以下の制約があります。

- `pkgs/`直下の`.nix`は全てパッケージとして`callPackage`されるので、補助のファイルは直下に置けない
- `package.nix`を持つディレクトリでは、他の`.nix`は拾われない
- `package.nix`を持たないサブディレクトリは入れ子の属性集合になり、flakeの`packages`と`checks`では扱えない
- `callPackage`で包むと`.override`が変わって困るもの(`lib/linux-xanmod-server.nix`のカーネル)は`lib/`に置く

overlayは`prev`を見ずに上書きするので、
nixpkgsと同じ名前のパッケージを置くとnixpkgsの中の依存まで差し替わります。
`checks`の`local-packages-name-collision`が衝突を検出するので、
落ちたらnixpkgsの方へ移行するか名前を変えるかを決めます。

`flake.nix`の`localPackages`には、
CIで確かめる時だけの例外があります。
`plamo-translate-cli`はCUDAをビルドしないCPU版のllama.cppとモデルの名前を渡します。
