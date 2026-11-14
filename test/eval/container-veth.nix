# `lib/container-veth.nix`が、
# IPv4を持つコンテナにはIPv6とIPv4の両方を、
# 持たないコンテナにはIPv6だけを設定することを確かめる。
#
# systemd-networkdの設定とpostStartの`ip`のコマンドの両方で出し分けているので、
# 条件を取り違えると、
# IPv4を持たないコンテナに`null`を渡す`ip`のコマンドが入ったり、
# IPv4を持つコンテナからIPv4が抜けたりする。
# どちらも評価は通るので、実機でコンテナを起動するまで気付けない。
{ lib }:
let
  name = "test";
  dualAddr = {
    host6 = "fdf2:a855:5a3f:100::90";
    guest6 = "fdf2:a855:5a3f:100::91";
    host4 = "192.168.100.90";
    guest4 = "192.168.100.91";
  };
  ipv6OnlyAddr = dualAddr // {
    host4 = null;
    guest4 = null;
  };
  veth = addr: import ../../lib/container-veth.nix { inherit lib name addr; };
  dual = veth dualAddr;
  ipv6Only = veth ipv6OnlyAddr;
  networkOf = v: v.network.networks."20-${name}-veth";
  # `mkForce`で包んでいるので中身を取り出す。
  postStartOf = v: v.services."container@${name}".postStart.content;
in
assert lib.assertMsg (
  (networkOf dual).addresses == [
    { Address = "fdf2:a855:5a3f:100::90/128"; }
    { Address = "192.168.100.90/32"; }
  ]
) "IPv4を持つコンテナのホスト側のアドレスが違います";
assert lib.assertMsg (
  (networkOf dual).routes == [
    { Destination = "fdf2:a855:5a3f:100::91/128"; }
    { Destination = "192.168.100.91/32"; }
  ]
) "IPv4を持つコンテナのホスト側の経路が違います";
assert lib.assertMsg (lib.all (command: lib.hasInfix command (postStartOf dual)) [
  "ip -6 addr add fdf2:a855:5a3f:100::90 "
  "ip -6 route add fdf2:a855:5a3f:100::91 "
  "ip addr add 192.168.100.90 "
  "ip route add 192.168.100.91 "
]) "IPv4を持つコンテナのpostStartにIPv6とIPv4の両方のコマンドがありません";
assert lib.assertMsg (
  (networkOf ipv6Only).addresses == [ { Address = "fdf2:a855:5a3f:100::90/128"; } ]
) "IPv4を持たないコンテナのホスト側のアドレスが違います";
assert lib.assertMsg (
  (networkOf ipv6Only).routes == [ { Destination = "fdf2:a855:5a3f:100::91/128"; } ]
) "IPv4を持たないコンテナのホスト側の経路が違います";
assert lib.assertMsg (
  !(lib.hasInfix "ip addr add" (postStartOf ipv6Only))
  && !(lib.hasInfix "ip route add" (postStartOf ipv6Only))
) "IPv4を持たないコンテナのpostStartにIPv4のコマンドがあります";
# 個別の値を見落としても、`null`が値や文字列に紛れ込めばここで分かる。
# postStartはエラーを`/dev/null`へ捨てているので、それは除いて探す。
assert lib.assertMsg (
  !(lib.hasInfix "null" (lib.replaceStrings [ "/dev/null" ] [ "" ] (postStartOf ipv6Only)))
  && !(lib.hasInfix "null" (builtins.toJSON (networkOf ipv6Only)))
) "IPv4を持たないコンテナの設定に`null`が紛れ込んでいます";
true
