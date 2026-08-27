# このtailnetのMagicDNSのsuffix。
#
# `nixos/core/tailscale.nix`の`local.tailscale.tailnet`の既定値がこれを読みます。
# NixOSモジュールからはそのオプション経由で参照してください。
#
# home-managerの設定はNixOSの`config`を読めないため、
# tailnet内の名前を組み立てる時にこのファイルを直接importします。
# 同じ文字列を両方にリテラルで書くと、
# tailnetを移した時に片方だけが古いまま残ります。
"border-saurolophus.ts.net"
