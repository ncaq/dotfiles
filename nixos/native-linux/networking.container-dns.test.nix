# コンテナのsystemd-resolvedのフォールバックのDNSが、
# コンテナの持つアドレスファミリに合っていることを確かめる。
# `nixos/native-linux/networking.nix`が全てのコンテナへ入れている設定です。
#
# 条件を取り違えると、評価もブートも通ったまま次のどちらかになる。
#
# - IPv4を持たないコンテナにIPv4のサーバが残り、
#   先頭のIPv6のサーバが応答しない時に届かないサーバへ切り替わる
# - IPv4を持つコンテナからIPv4のサーバが抜けたり、IPv4のサーバが先に並んだりする
#
# 以下の3つのコンテナで見る。
#
# - 自分のネットワークとIPv4のアドレスを持つコンテナは、IPv6のサーバを先に並べ、続けてIPv4のサーバも持つ
# - 自分のネットワークを持つがIPv4のアドレスを持たないコンテナは、IPv6のサーバだけを持つ
# - 自分のネットワークを持たないコンテナは、ホストのIPv4を使えるのでIPv4のサーバも持つ
#
# どのコンテナがIPv4を持つかの期待値は、実装の式を書き写さずにコンテナごとに手で決める。
# 書き写すと、式を取り違えても期待値も同じように取り違えて通ってしまう。
#
# `networking.nix`だけを`lib.evalModules`で読み込み、
# 参照している他のオプションは最小の形で用意する。
{ lib }:
let
  publicDns = import ../../lib/public-dns.nix;
  format = map (server: "${server.address}#${server.name}");
  ipv6Servers = format publicDns.ipv6;
  ipv4Servers = format publicDns.ipv4;

  stub = {
    options = {
      # `networking.nix`がホストへ入れる設定を受けるだけ。
      networking = lib.mkOption {
        type = lib.types.anything;
        default = { };
      };
      programs = lib.mkOption {
        type = lib.types.anything;
        default = { };
      };
      services = lib.mkOption {
        type = lib.types.anything;
        default = { };
      };
      systemd = lib.mkOption {
        type = lib.types.anything;
        default = { };
      };
      # `nixos-containers.nix`のうち、`networking.nix`が読むものと書くものだけ。
      containers = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              privateNetwork = lib.mkOption {
                type = lib.types.bool;
                default = false;
              };
              localAddress = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              config = lib.mkOption {
                type = lib.types.anything;
                default = { };
              };
            };
          }
        );
        default = { };
      };
    };
  };

  evaluated = lib.evalModules {
    modules = [
      ./networking.nix
      stub
      {
        containers = {
          dual = {
            privateNetwork = true;
            localAddress = "192.168.100.11";
          };
          ipv6Only = {
            privateNetwork = true;
          };
          hostNetwork = { };
        };
      }
    ];
  };
  fallbackOf =
    name: evaluated.config.containers.${name}.config.services.resolved.settings.Resolve.FallbackDNS;
in
# 一覧が空だと、以下の比較がどれも空同士で通ってしまう。
assert lib.assertMsg (ipv6Servers != [ ] && ipv4Servers != [ ]) "公開DNSの一覧が空です";
assert lib.assertMsg (
  fallbackOf "dual" == ipv6Servers ++ ipv4Servers
) "IPv4を持つコンテナのフォールバックがIPv6のサーバの後ろにIPv4のサーバを並べていません: ${builtins.toJSON (fallbackOf "dual")}";
assert lib.assertMsg (
  fallbackOf "ipv6Only" == ipv6Servers
) "IPv4を持たないコンテナのフォールバックがIPv6のサーバだけになっていません: ${builtins.toJSON (fallbackOf "ipv6Only")}";
assert lib.assertMsg (
  fallbackOf "hostNetwork" == ipv6Servers ++ ipv4Servers
) "ホストのネットワークを使うコンテナのフォールバックにIPv4のサーバがありません: ${builtins.toJSON (fallbackOf "hostNetwork")}";
true
