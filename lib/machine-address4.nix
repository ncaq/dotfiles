/**
  コンテナとmicroVMのIPv4アドレスを、同じマシンのIPv6アドレスから導く関数。

  コンテナやmicroVMとホストの間、
  コンテナやmicroVM同士のやり取りはIPv6で行い、
  マシンのアドレスもIPv6で宣言する。
  IPv4を持たせるのは、
  github.comのようなIPv4でしか繋がらないインターネットの宛先へ出る必要があるマシンだけで、
  そのマシンにだけこの関数で導いたIPv4を付ける。
  IPv4のアドレスを別に宣言せずに導くのは、
  使う側がIPv4を持つかどうかだけを選べば済むようにするため。

  # IPv6アドレスの体系

  ホストが上流から貰えるIPv6は自宅LANの/64が1つだけで、
  prefix delegationは無いのでコンテナへ配れるグローバルなプレフィックスが無い。
  なのでコンテナにはULA(RFC 4193)を付けて、
  ホストがNATモジュールの`enableIPv6`でmasqueradeして外へ出す。
  IPv4を持つマシンはIPv4も同じようにmasqueradeして外へ出す。

  ULAを送信元に持つ機器はRFC 6724の宛先選択でIPv4を先に並べるので、
  IPv4も持つマシンがインターネットへ出る時は、
  getaddrinfoの順に繋ぐ実装(Goのnetやurllib3など)ではIPv4が先になり、
  グローバルなIPv6を持つ場合のようにIPv6が優先はされない。
  curlのようにHappy EyeballsでIPv6から試す実装ではIPv6が先になる。
  どちらでもIPv6でしか繋がらない宛先に届き、
  IPv4側が不調の時はIPv6へ倒れる。
  ホストやコンテナの間はIPv6のアドレスを直接指定して繋ぐので、
  この並び順の影響は受けない。

  プレフィックスはRFC 4193の手順に従って乱数で決めた/48で、
  tailnetのfd7a:115c:a1e0::/48とは重ならない。
  ホストごとに独立したネットワークなので複数のホストで同じ値を使って構わない。
  IPv4の192.168.100.0/24も同じ扱いになっている。

  # IPv4への写し方

  `fdf2:a855:5a3f:<サブネット>::<ホスト>`を192.168.<サブネット>.<ホスト>へ写す。
  サブネットとホストの部分は10進の0-255に見える数字だけで書き、
  その字面をそのままIPv4のオクテットにする。
  `fdf2:a855:5a3f:100::11`は`192.168.100.11`になる。
  数値としては一致しない(0x11は17)が、
  IPv4とIPv6を並べて読んだ時に同じマシンだと分かることを優先した。
  サブネットとホストをそのまま写すので対応は単射で、
  IPv6が互いに違えばIPv4も互いに違う。

  IPv6アドレスの読み取りはnixpkgsの`lib.network.ipv6.fromString`に任せる。
  0の省略や大文字小文字や各部分の先頭の0のような書き方の違いは、
  省略しない小文字の形へ揃えてから見るので、
  同じアドレスなら書き方によらず同じIPv4になる。

  受け付けるのは上の形で、
  サブネットとホストが16進として読んだ時に10進の0-255にも見えるものだけ。
  `::1a`のような16進の文字を含むものや`::256`を写すと、
  評価は通るのに実機で`ip`が拒否して初めて壊れる。
  検査は`test/eval/machine-address4.nix`で固定している。

  # 引数

  - `lib`: IPv6アドレスの読み取りと文字列操作に使う
  - `ipv6`: 同じマシンのIPv6アドレス。プレフィックス長は付けない
*/
{ lib, ipv6 }:
let
  # コンテナとmicroVMに配るULAの/48のプレフィックス`fdf2:a855:5a3f::/48`を、
  # `fromString`が揃えた形の先頭3つの部分として並べたもの。
  #
  # 先頭の`fd`はRFC 4193でローカルに割り当てたULAであることを表す固定の値で、
  # 続く40ビットの`f2:a855:5a3f`がGlobal IDになる。
  # Global IDはULAのプレフィックスが他のネットワークと重ならないための乱数で、
  # RFC 4193の手順に従って一度だけ生成して以後は固定している。
  # 意味のある値ではないので変える理由は無く、
  # 変えると宣言している全てのアドレスとinfra.ncaq.netのtailnetの経路も変わる。
  #
  # IPv4へ写す時はこの部分を捨てるので、
  # ここが違うアドレスを受け付けると別のネットワークのアドレスと同じIPv4になる。
  prefix = [
    "fdf2"
    "a855"
    "5a3f"
  ];
  # 読めない入力は`fromString`が`throw`するので、
  # 下の検査で自分のメッセージを出せるように捕まえる。
  # 返り値の属性は遅延評価されるので、中まで評価して捕まえる。
  parsed =
    let
      address = lib.network.ipv6.fromString ipv6;
      result = builtins.tryEval (builtins.deepSeq address address);
    in
    if result.success then result.value else null;
  pieces = if parsed == null then [ ] else lib.splitString ":" parsed.address;
  subnet = lib.elemAt pieces 3;
  host = lib.elemAt pieces 7;
  # 揃えた後の各部分は先頭に0を持たないので、
  # 10進の数字だけで書かれていれば10進の字面としても曖昧さが無い。
  isOctet = s: builtins.match "[0-9]{1,3}" s != null && lib.toIntBase10 s <= 255;
  valid =
    # `fromString`はプレフィックス長を省くと128とみなすので、
    # 付いていたかは入力の字面で見る。
    !(lib.hasInfix "/" ipv6)
    && lib.length pieces == 8
    && lib.take 3 pieces == prefix
    &&
      lib.sublist 4 3 pieces == [
        "0"
        "0"
        "0"
      ]
    && isOctet subnet
    && isOctet host;
in
assert lib.assertMsg valid
  "machine-address4: `${ipv6}`は`${lib.concatStringsSep ":" prefix}:<サブネット>::<ホスト>`の形ではありません。サブネットとホストは10進の0-255に見える数字で書きます";
"192.168.${subnet}.${host}"
