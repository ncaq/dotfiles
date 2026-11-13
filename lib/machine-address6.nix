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

  192.168.0.0/16をこの/48へ写す。
  第3オクテットをサブネットに、第4オクテットをホストに、
  それぞれそのまま16進の見た目で写す。
  192.168.100.11は`fdf2:a855:5a3f:100::11`になる。
  数値としては一致しない(0x11は17)が、
  IPv4とIPv6を並べて読んだ時に同じマシンだと分かることを優先した。
  第3と第4のオクテットをそのまま写すので対応は単射で、
  IPv4が互いに違えばIPv6も互いに違う。
  先頭2オクテットは捨てるので192.168以外は受け付けない。
  通すと別の/16と衝突する。

  受け付けるのは10進の0-255を4つ並べたIPv4アドレスだけ。
  `a.b.c.d`のような文字列をそのまま埋め込むと、
  評価は通るのに実機で`ip`が拒否して初めて壊れる。
  検査は`test/eval/machine-address6.nix`で固定している。

  # 引数

  - `lib`: 文字列操作に使う
  - `ipv4`: 同じマシンのIPv4アドレス。プレフィックス長は付けない
*/
{ lib, ipv4 }:
let
  prefix = "fdf2:a855:5a3f";
  octets = lib.splitString "." ipv4;
  # 10進の0-255だけを通す。
  # `lib.toIntBase10`は符号や空文字列を受け付けないが、
  # 先頭の0は通すので正規表現で字面も縛る。
  isOctet =
    s:
    builtins.match "[0-9]{1,3}" s != null
    && (
      let
        n = lib.toIntBase10 s;
      in
      0 <= n && n <= 255
    );
in
assert lib.assertMsg (
  lib.length octets == 4 && lib.all isOctet octets
) "machine-address6: `${ipv4}`はIPv4アドレスではありません";
assert lib.assertMsg (
  lib.take 2 octets == [
    "192"
    "168"
  ]
) "machine-address6: `${ipv4}`は192.168.0.0/16の外です。先頭2オクテットは写さないので他の/16は衝突します";
"${prefix}:${lib.elemAt octets 2}::${lib.elemAt octets 3}"
