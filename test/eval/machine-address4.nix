# `lib/machine-address4.nix`が、
# IPv6アドレスを単射でIPv4へ写し、
# 写せる形でない入力を拒否することを確かめる。
#
# この関数は`machineAddresses`を通らない呼び出し(bulletのcomfyuiやollama)もあるので、
# `machine-mapping.nix`の重複assertionには頼れない。
# サブネットの写し忘れや、
# 10進でない部分の素通りは実機に適用するまで見えないため、
# 評価時に固定しておく。
{ lib }:
let
  toAddress4 = ipv6: import ../../lib/machine-address4.nix { inherit lib ipv6; };
  rejects = ipv6: !(builtins.tryEval (builtins.deepSeq (toAddress4 ipv6) true)).success;
in
assert lib.assertMsg (
  toAddress4 "fdf2:a855:5a3f:100::11" == "192.168.100.11"
) "ドキュメントの例と違う結果になりました: ${toAddress4 "fdf2:a855:5a3f:100::11"}";
# サブネットはIPv6のサブネットの部分から導く。
# 固定にすると`101::11`と`100::11`が同じIPv4になって、一意性が崩れる。
assert lib.assertMsg (
  toAddress4 "fdf2:a855:5a3f:101::11" == "192.168.101.11"
) "サブネットが第3オクテットに写されていません: ${toAddress4 "fdf2:a855:5a3f:101::11"}";
assert lib.assertMsg (toAddress4 "fdf2:a855:5a3f:0::1" == "192.168.0.1") "0を扱えません";
assert lib.assertMsg (toAddress4 "fdf2:a855:5a3f:255::255" == "192.168.255.255") "255を扱えません";
# 同じアドレスの別の書き方は同じIPv4へ写す。
# 字面のまま写すと、
# 同じマシンのつもりの2つの宣言が別のIPv4になったり、
# `::011`の先頭の0がIPv4で8進として読まれたりする。
assert lib.assertMsg (
  toAddress4 "fdf2:a855:5a3f:100:0:0:0:11" == "192.168.100.11"
) "0を省略しない書き方を同じアドレスとして扱えません";
assert lib.assertMsg (
  toAddress4 "FDF2:A855:5A3F:100::11" == "192.168.100.11"
) "大文字の書き方を同じアドレスとして扱えません";
assert lib.assertMsg (
  toAddress4 "fdf2:a855:5a3f:0100::011" == "192.168.100.11"
) "先頭に0を持つ書き方を同じアドレスとして扱えません";
# 決めた形でないアドレスを拒否する。
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100:1::11") "サブネットとホストの間が0でない入力を通しました";
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100::1:11") "ホストの部分が2つある入力を通しました";
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100::11/128") "プレフィックス長付きの入力を通しました";
assert lib.assertMsg (rejects "192.168.100.11") "IPv4アドレスを通しました";
# 10進の0-255でない部分を拒否する。
# `::1a`は`192.168.100.1a`に、`::256`は`192.168.100.256`になってしまう。
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100::1a") "16進の文字を通しました";
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100::256") "255を超える部分を通しました";
assert lib.assertMsg (rejects "fdf2:a855:5a3f:256::11") "255を超えるサブネットを通しました";
# IPv6アドレスとして読めない入力を拒否する。
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100::11::1") "`::`が2つある入力を通しました";
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100::g") "16進でない文字を通しました";
# 写せるのはこのプレフィックスだけ。
# プレフィックスは捨てるので、それ以外を通すと別のネットワークと衝突する。
assert lib.assertMsg (rejects "fd7a:115c:a1e0:100::11") "別のプレフィックスを通しました";
true
