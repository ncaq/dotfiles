# nixos

NixOSのシステム設定です。
`configuration.nix`がエントリポイントで`core/`をimportします。
ホストごとの設定(`host/<名前>.nix`)が、
必要な層を選んでimportします。
`mk-nixos-system.nix`は、
`flake.nix`がこれらからホストの構成を組み立てるための関数です。

- `client/`: 人が直接操作するクライアントPC向けのGUIなどの設定。サーバには適用しない
- `core/`: 全てのNixOSホストに共通の設定
- `desktop/`: 据え置きのデスクトップPCに固有の設定。ラップトップPCには適用しない
- `gaming/`: ゲームをするホスト向けの設定
- `host/`: ホストごとの設定
- `laptop/`: ラップトップPCに固有の設定。据え置きのデスクトップPCには適用しない
- `native-linux/`: ネイティブLinux環境(WSLではない)の設定
- `ollama/`: Ollamaを動かすホスト向けの設定
- `server/`: サーバに固有の設定。クライアントPCには適用しない
- `wsl/`: WSL2環境専用の設定

WSLのホストが読み込むのは`core/`と`wsl/`だけです。
`client/`か`server/`を読み込むホストは、
`flake.nix`の`hostInfo`にも`client = true`か`server = true`を書きます。
home-managerは`client`を見てGUIの設定を読み込みます。

NixOS Containerの定義の定型は、
`native-linux/container-template.nix`が既定値と`containers.<name>.local`の宣言から生成します。
個々のコンテナの定義には、そのコンテナに固有のことだけを書きます。

各ディレクトリの`default.nix`は`importDirModules`で中の`.nix`を全て読み込むので、
ファイルを足すだけで有効になります。
仕組みは`lib/import-dir-modules.nix`に書いてあります。
