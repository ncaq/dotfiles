# `lib/machine-address6.nix`が、
# IPv4アドレスを単射でULAへ写し、
# IPv4アドレスでない入力を拒否することを確かめる。
#
# この関数は`machineAddresses`を通らない呼び出し(bulletのcomfyuiやollama)もあるので、
# `machine-mapping.nix`の重複assertionには頼れない。
# サブネットの写し忘れや、
# 10進でないオクテットの素通りは実機に適用するまで見えないため、
# 評価時に固定しておく。
{ lib }:
let
  toAddress6 = ipv4: import ../../lib/machine-address6.nix { inherit lib ipv4; };
  rejects = ipv4: !(builtins.tryEval (builtins.deepSeq (toAddress6 ipv4) true)).success;
in
assert lib.assertMsg (
  toAddress6 "192.168.100.11" == "fdf2:a855:5a3f:100::11"
) "ドキュメントの例と違う結果になりました: ${toAddress6 "192.168.100.11"}";
# サブネットは第3オクテットから導く。
# 固定にすると192.168.101.11と192.168.100.11が同じIPv6になって、一意性が崩れる。
assert lib.assertMsg (
  toAddress6 "192.168.101.11" == "fdf2:a855:5a3f:101::11"
) "第3オクテットがサブネットに写されていません: ${toAddress6 "192.168.101.11"}";
assert lib.assertMsg (toAddress6 "192.168.0.1" == "fdf2:a855:5a3f:0::1") "0のオクテットを扱えません";
assert lib.assertMsg (toAddress6 "192.168.255.255" == "fdf2:a855:5a3f:255::255") "255のオクテットを扱えません";
# オクテットの数が4でない入力を拒否する。
assert lib.assertMsg (rejects "192.168.100") "オクテットが3つしか無い入力を通しました";
assert lib.assertMsg (rejects "192.168.100.11.1") "オクテットが5つある入力を通しました";
assert lib.assertMsg (rejects "fdf2::1") "IPv6アドレスを通しました";
# 10進の0-255でないオクテットを拒否する。
# `a.b.c.d`はそのまま`::d`に、`1.2.3.999`は`::999`になってしまう。
assert lib.assertMsg (rejects "a.b.c.d") "数字でないオクテットを通しました";
assert lib.assertMsg (rejects "192.168.100.999") "255を超えるオクテットを通しました";
assert lib.assertMsg (rejects "192.168.100.-1") "負のオクテットを通しました";
assert lib.assertMsg (rejects "192.168.100.") "空のオクテットを通しました";
assert lib.assertMsg (rejects "192.168.100.11/32") "プレフィックス長付きの入力を通しました";
# 写せるのは192.168.0.0/16だけ。
# 先頭2オクテットは捨てるので、それ以外を通すと別の/16と衝突する。
assert lib.assertMsg (rejects "10.0.100.11") "192.168以外の先頭2オクテットを通しました";
assert lib.assertMsg (rejects "192.169.100.11") "192.168以外の先頭2オクテットを通しました";
true
