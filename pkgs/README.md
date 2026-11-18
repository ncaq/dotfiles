# pkgs

自作のパッケージです。
`lib/local-packages-overlay.nix`が`lib.packagesFromDirectoryRecursive`で走査して、
全環境で共通のoverlayとしてnixpkgsのトップレベルに生やします。

`pkgs/<名前>.nix`か`pkgs/<名前>/package.nix`を置くだけで、
モジュールからは`pkgs.<名前>`として使え、
flakeの`packages`と`checks`にも加わります。
`flake.nix`やモジュールでパスを指定して`callPackage`する必要はありません。
ホストの設定に合わせた引数を渡したい時は`pkgs.<名前>.override`を使います。

`himari-src`のようなnixpkgsに無いflakeのinputは、
overlayが`callPackage`の自動で渡す引数に足しています。
`home-manager`のように、
nixpkgsにあってもinputと版を揃えたいものも同じように足しています。

新しく書く時の言語の選び方は`docs/helper-program-language-policy.md`に書いてあります。

## テスト

パッケージの`passthru.tests`に置いたderivationも、
`<名前>-test-<テストの名前>`として`checks`に加わります。
`comfyui-ncaq-nodes`のように、
テストを書き換えただけで配るもののstoreパスが変わると困る時に、
`checkPhase`の代わりに使います。

各言語のテストは、
その言語のツールが期待する場所(`<名前>/test`など)に置きます。

## 制約

置くだけで拾われる裏返しとして、
以下の制約があります。

- `pkgs/`直下の`.nix`は全てパッケージとして`callPackage`されるので、補助のファイルは直下に置けない
- `package.nix`を持つディレクトリでは、`renovate-recovery/claude-config.nix`のような他の`.nix`は拾われない
- `package.nix`を持たないサブディレクトリは入れ子の属性集合になり、flakeの`packages`と`checks`では扱えない
- `callPackage`で包むと`.override`が変わって困るもの(`lib/linux-xanmod-server.nix`のカーネル)は`lib/`に置く

overlayは`prev`を見ずに上書きするので、
nixpkgsと同じ名前のパッケージを置くとnixpkgsの中の依存まで差し替わります。
`checks`の`local-packages-name-collision`が衝突を検出するので、
落ちたらnixpkgsの方へ移行するか名前を変えるかを決めます。

`flake.nix`の`localPackages`には、
CIで確かめる時だけの例外があります。
`plamo-translate-cli`はCUDAをビルドしないCPU版のllama.cppとモデルの名前を渡します。
