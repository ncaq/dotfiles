# `lib/parse-ipv6.nix`が、
# プレフィックス長の無いIPv6アドレスだけを読んで省略しない形に揃え、
# それ以外を`null`にすることを確かめる。
#
# `machine-address4`と`machineAddresses`の重複の検査と、
# `machine-egress`の`destinations`の型の検査が、どれもこの関数で判定している。
# 読めない入力で例外が漏れたり、
# 書き方の違いで揃わなかったりすると、
# それらの検査が黙って崩れる。
{ lib }:
let
  parseIpv6 = import ../../lib/parse-ipv6.nix { inherit lib; };
  expanded = "fdf2:a855:5a3f:100:0:0:0:11";
in
assert lib.assertMsg (
  parseIpv6 "fdf2:a855:5a3f:100::11" == expanded
) "省略形を揃えられません: ${toString (parseIpv6 "fdf2:a855:5a3f:100::11")}";
# 書き方だけが違う同じアドレスは同じ形になる。
assert lib.assertMsg (parseIpv6 expanded == expanded) "省略しない形をそのまま返しません";
assert lib.assertMsg (parseIpv6 "FDF2:A855:5A3F:100::11" == expanded) "大文字を小文字に揃えられません";
assert lib.assertMsg (parseIpv6 "fdf2:a855:5a3f:0100::011" == expanded) "各部分の先頭の0を揃えられません";
# IPv6アドレスでないものは`null`にして、例外を漏らさない。
assert lib.assertMsg (parseIpv6 "192.168.100.11" == null) "IPv4アドレスを通しました";
assert lib.assertMsg (parseIpv6 "fdf2::g" == null) "16進でない文字を通しました";
assert lib.assertMsg (parseIpv6 "fdf2::1::2" == null) "`::`が2つある入力を通しました";
assert lib.assertMsg (parseIpv6 "" == null) "空の入力を通しました";
# アドレス1つを指定する所で範囲を渡せないように、プレフィックス長付きは読まない。
assert lib.assertMsg (parseIpv6 "fdf2::1/128" == null) "プレフィックス長付きの入力を通しました";
true
