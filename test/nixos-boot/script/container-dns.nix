# コンテナのsystemd-resolvedのフォールバックのDNSが、
# コンテナの持つアドレスファミリに合っていることを評価時に確かめます。
# `nixos/native-linux/networking.nix`が全てのコンテナへ入れている設定です。
#
# 条件を取り違えると、評価もブートも通ったまま次のどちらかになります。
#
# - IPv4を持たないコンテナにIPv4のサーバが残り、
#   先頭のIPv6のサーバが応答しない時に届かないサーバへ切り替わる
# - IPv4を持つコンテナからIPv4のサーバが抜けたり、IPv4のサーバが先に並んだりする
#
# 以下を見ます。
#
# - IPv4を持たないコンテナはIPv6のサーバだけを持つこと
# - IPv4を持つコンテナはIPv6のサーバを先に並べ、続けてIPv4のサーバも持つこと
#
# IPv4を持つかの期待値は、実装の式を書き写すと取り違えても同じ判定をして通るので、
# seminarの`machineAddresses`の`ipv4`という実装より上流の宣言で決めます。
# seminarにはIPv4を持つコンテナと持たないコンテナの両方が宣言されているので、
# 実装の式を取り違えればここで食い違います。
# 宣言の無いコンテナ(ネットワークを持たないpostgresqlや、bulletのコンテナ)は、
# 実装と同じ式で期待値を出して、並び順と出し分けだけを見ます。
#
# 実機の構成の値だけで決まるので、テストVMの中では何もしません。
{ lib, config, ... }:
let
  # `<address>#<name>`のアドレスの部分がIPv6か。
  isIpv6 = server: lib.hasInfix ":" (lib.head (lib.splitString "#" server));
  machineAddresses = config.machineAddresses or { };
  check =
    name: c:
    let
      servers = c.config.services.resolved.settings.Resolve.FallbackDNS;
      hasIpv4 =
        if machineAddresses ? ${name} then
          machineAddresses.${name}.ipv4
        else
          !c.privateNetwork || c.localAddress != null;
      ipv6Servers = lib.filter isIpv6 servers;
      ipv4Servers = lib.filter (s: !isIpv6 s) servers;
    in
    if ipv6Servers == [ ] then
      "${name}: IPv6のサーバがありません"
    else if !hasIpv4 && ipv4Servers != [ ] then
      "${name}: IPv4を持たないのにIPv4のサーバがあります"
    else if hasIpv4 && ipv4Servers == [ ] then
      "${name}: IPv4を持つのにIPv4のサーバがありません"
    else if servers != ipv6Servers ++ ipv4Servers then
      "${name}: IPv6のサーバが先に並んでいません"
    else
      null;
  problems = lib.filter (p: p != null) (lib.mapAttrsToList check config.containers);
in
assert lib.assertMsg (
  problems == [ ]
) "コンテナのフォールバックのDNSがアドレスファミリに合っていません: ${lib.concatStringsSep "; " problems}";
""
