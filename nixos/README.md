# nixos

NixOSのシステム設定です。
`configuration.nix`がエントリポイントで`core/`をimportします。
ホストごとの設定(`host/<名前>.nix`)が、
必要な層を選んでimportします。

- `client/`: 人が直接操作するクライアントPC向けの設定。サーバには適用しない
- `core/`: 全てのNixOSホストに共通の設定
- `desktop/`: 据え置きのデスクトップPCに固有の設定。ラップトップPCには適用しない
- `gaming/`: ゲームをするホスト向けの設定
- `host/`: ホストごとの設定
- `laptop/`: ラップトップPCに固有の設定。据え置きのデスクトップPCには適用しない
- `native-linux/`: ネイティブLinux環境(WSLではない)の設定
- `ollama/`: Ollamaを動かすホスト向けの設定
- `server/`: サーバに固有の設定。クライアントPCには適用しない
- `wsl/`: WSL2環境専用の設定

各ディレクトリの`default.nix`は`importDirModules`で中の`.nix`を全て読み込むので、
ファイルを足すだけで有効になります。
仕組みは`lib/import-dir-modules.nix`に書いてあります。

## seminar

自宅サーバです。
ローカルネットワークとtailnetへ様々なサービスを公開していて、
一部はCloudflare Tunnelでインターネットにも公開しています。

サービスのうち隔離が容易で隔離する意味のあるものは、
[NixOS Containers](https://wiki.nixos.org/wiki/NixOS_Containers)か、
[microvm.nix](https://github.com/microvm-nix/microvm.nix)で隔離しています。

大容量のデータは`/mnt/noa`のbtrfs RAID 1に置いています。

PostgreSQLはコンテナで動かしています。
クライアントはbind mountしたUnixソケット(`/run/postgresql`)へ、
peer認証で接続します。
