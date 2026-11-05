/**
  コンテナとmicroVMのIPv6アドレスを、同じマシンのIPv4アドレスから導く関数。

  ホストが上流から貰えるIPv6は自宅LANの/64が1つだけで、
  prefix delegationは無いのでコンテナへ配れるグローバルなプレフィックスが無い。
  なのでコンテナにはULA(RFC 4193)を付けて、
  ホストがNATモジュールの`enableIPv6`でmasqueradeして外へ出す。
  IPv4の192.168.100.0/24とmasqueradeの構成をそのままIPv6へ写した形になる。

  ULAを送信元に持つ機器はRFC 6724の宛先選択でIPv4を先に並べるので、
  getaddrinfoの順に繋ぐ実装(Goのnetやurllib3など)ではIPv4が先になり、
  グローバルなIPv6を持つ場合のようにIPv6が優先はされない。
  curlのようにHappy EyeballsでIPv6から試す実装ではIPv6が先になる。
  どちらでもIPv6でしか繋がらない宛先に届き、
  IPv4側が不調の時はIPv6へ倒れる。

  プレフィックスはRFC 4193の手順に従って乱数で決めた/48で、
  tailnetのfd7a:115c:a1e0::/48とは重ならない。
  ホストごとに独立したネットワークなので複数のホストで同じ値を使って構わない。
  IPv4の192.168.100.0/24も同じ扱いになっている。

  サブネットはIPv4の第3オクテットの100を、
  下位はIPv4の第4オクテットを、それぞれそのまま16進の見た目で写す。
  192.168.100.11は`fdf2:a855:5a3f:100::11`になる。
  数値としては一致しない(0x11は17)が、
  IPv4とIPv6を並べて読んだ時に同じマシンだと分かることを優先した。
  アドレスの一意性はIPv4側のassertionが保証する。

  # 引数

  - `lib`: 文字列操作に使う
  - `ipv4`: 同じマシンのIPv4アドレス。プレフィックス長は付けない
*/
{ lib, ipv4 }:
let
  prefix = "fdf2:a855:5a3f:100";
  octets = lib.splitString "." ipv4;
in
assert lib.assertMsg (lib.length octets == 4) "machine-address6: `${ipv4}`はIPv4アドレスではありません";
"${prefix}::${lib.last octets}"
