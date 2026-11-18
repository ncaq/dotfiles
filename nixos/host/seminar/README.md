# seminar

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
