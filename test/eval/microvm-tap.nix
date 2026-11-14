# `lib/microvm-tap.nix`が、
# IPv4を持つマシンにはIPv6とIPv4の両方を、
# 持たないマシンにはIPv6だけを設定することを確かめる。
#
# IPv4を持つかどうかで出し分けているので、
# 条件を取り違えると、
# IPv4を持たないゲストに`null/24`のような壊れた値やIPv4のDNSが入ったり、
# IPv4を持つゲストからIPv4が抜けたりする。
# どちらも評価は通るので、実機でVMを起動するまで気付けない。
{ lib }:
let
  publicDns = import ../../lib/public-dns.nix;
  addresses = servers: map (server: server.address) servers;
  tap = "vm-test";
  dualAddr = {
    host6 = "fdf2:a855:5a3f:100::30";
    guest6 = "fdf2:a855:5a3f:100::31";
    host4 = "192.168.100.30";
    guest4 = "192.168.100.31";
  };
  ipv6OnlyAddr = dualAddr // {
    host4 = null;
    guest4 = null;
  };
  network = addr: import ../../lib/microvm-tap.nix { inherit tap addr; };
  dual = network dualAddr;
  ipv6Only = network ipv6OnlyAddr;
  guestConfig = n: n.guest.networks."20-lan".networkConfig;
  host = n: n.host."20-${tap}";
in
assert lib.assertMsg (
  (guestConfig dual).Address == [
    "fdf2:a855:5a3f:100::31/64"
    "192.168.100.31/24"
  ]
) "IPv4を持つゲストのアドレスが違います";
assert lib.assertMsg (
  (guestConfig dual).Gateway == [
    "fdf2:a855:5a3f:100::30"
    "192.168.100.30"
  ]
) "IPv4を持つゲストのゲートウェイが違います";
assert lib.assertMsg (
  (guestConfig dual).DNS == addresses publicDns.ipv6 ++ addresses publicDns.ipv4
) "IPv4を持つゲストのDNSがIPv6を先にした両方になっていません";
assert lib.assertMsg (
  (host dual).addresses == [
    { Address = "fdf2:a855:5a3f:100::30/128"; }
    { Address = "192.168.100.30/32"; }
  ]
) "IPv4を持つマシンのホスト側のアドレスが違います";
assert lib.assertMsg (
  (host dual).routes == [
    { Destination = "fdf2:a855:5a3f:100::31/128"; }
    { Destination = "192.168.100.31/32"; }
  ]
) "IPv4を持つマシンのホスト側の経路が違います";
assert lib.assertMsg (
  (guestConfig ipv6Only).Address == [ "fdf2:a855:5a3f:100::31/64" ]
) "IPv4を持たないゲストのアドレスが違います";
assert lib.assertMsg (
  (guestConfig ipv6Only).Gateway == [ "fdf2:a855:5a3f:100::30" ]
) "IPv4を持たないゲストのゲートウェイが違います";
assert lib.assertMsg (
  (guestConfig ipv6Only).DNS == addresses publicDns.ipv6
) "IPv4を持たないゲストにIPv6以外のDNSがあります";
assert lib.assertMsg (
  (host ipv6Only).addresses == [ { Address = "fdf2:a855:5a3f:100::30/128"; } ]
) "IPv4を持たないマシンのホスト側のアドレスが違います";
assert lib.assertMsg (
  (host ipv6Only).routes == [ { Destination = "fdf2:a855:5a3f:100::31/128"; } ]
) "IPv4を持たないマシンのホスト側の経路が違います";
# 個別の値を見落としても、`null`が値や文字列に紛れ込めばここで分かる。
assert lib.assertMsg (
  !(lib.hasInfix "null" (builtins.toJSON ipv6Only))
) "IPv4を持たないマシンの設定に`null`が紛れ込んでいます";
true
