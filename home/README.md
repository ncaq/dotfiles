# home

home-managerの設定です。
`default.nix`がエントリポイントです。
`mk-linux-home-manager.nix`は、
`flake.nix`がNixOSを介さないhome-managerの構成を組み立てるための関数です。

- `client/`: 人が直接操作するGUIのあるネイティブLinux環境の設定。サーバには適用しない
- `core/`: 全環境で共通の設定
- `linked/`: シンボリックリンクで配置する設定ファイル
- `native-linux/`: ネイティブLinux環境(NixOSなど、WSLやTermuxではない環境)専用の設定
- `wsl/`: WSL2環境専用の設定

各ディレクトリの`default.nix`は`importDirModules`で中の`.nix`を全て読み込むので、
ファイルを足すだけで有効になります。
仕組みは`lib/import-dir-modules.nix`に書いてあります。
