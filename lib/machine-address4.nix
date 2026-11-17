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

  IPv6アドレスの読み取りは`lib/parse-ipv6.nix`に任せる。
  0の省略や大文字小文字や各部分の先頭の0のような書き方の違いは、
  省略しない小文字の形へ揃えてから見るので、
  同じアドレスなら書き方によらず同じIPv4になる。

  受け付けるのは上の形で、
  サブネットとホストが16進として読んだ時に10進の0-255にも見えるものだけ。
  `::1a`のような16進の文字を含むものや`::256`を写すと、
  評価は通るのに実機で`ip`が拒否して初めて壊れる。
  検査は末尾の`assert`で固定している。

  `lib`を渡すと表明が走り、IPv6アドレスを受け取る関数が返る。
  呼び出し側は関数を1度だけ束縛して使い回す。
  アドレスごとに`lib`から渡し直すと、変換のたびに表明が走り直す。

  ```nix
  toAddress4 = import ../../lib/machine-address4.nix { inherit lib; };
  toAddress4 "fdf2:a855:5a3f:100::11"
  => "192.168.100.11"
  ```

  # 引数

  - `lib`: IPv6アドレスの読み取りと文字列操作に使う
  - 返る関数の引数: 同じマシンのIPv6アドレス。プレフィックス長は付けない
*/
{ lib }:
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
  parseIpv6 = import ./parse-ipv6.nix { inherit lib; };
  # 揃えた後の各部分は先頭に0を持たないので、
  # 10進の数字だけで書かれていれば10進の字面としても曖昧さが無い。
  isOctet = s: builtins.match "[0-9]{1,3}" s != null && lib.toIntBase10 s <= 255;

  toAddress4 =
    address:
    let
      # 読めない入力やプレフィックス長付きの入力は`null`になるので、
      # 下の検査で自分のメッセージを出せる。
      parsed = parseIpv6 address;
      pieces = if parsed == null then [ ] else lib.splitString ":" parsed;
      subnet = lib.elemAt pieces 3;
      host = lib.elemAt pieces 7;
      valid =
        lib.length pieces == 8
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
      "machine-address4: `${address}`は`${lib.concatStringsSep ":" prefix}:<サブネット>::<ホスト>`の形ではありません。サブネットとホストは10進の0-255に見える数字で書きます";
    "192.168.${subnet}.${host}";

  rejects = address: !(builtins.tryEval (toAddress4 address)).success;
in
# この関数は`machineAddresses`を通らない呼び出し(bulletのcomfyuiやollama)もあるので、
# `machine-mapping.nix`の重複assertionには頼れない。
# サブネットの写し忘れや、
# 10進でない部分の素通りは実機に適用するまで見えないため、
# 評価時に固定しておく。
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
assert lib.assertMsg (rejects "fdf2:a855:5a3f:1a::11") "16進の文字を含むサブネットを通しました";
# IPv6アドレスとして読めない入力を拒否する。
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100::11::1") "`::`が2つある入力を通しました";
assert lib.assertMsg (rejects "fdf2:a855:5a3f:100::g") "16進でない文字を通しました";
# 写せるのはこのプレフィックスだけ。
# プレフィックスは捨てるので、それ以外を通すと別のネットワークと衝突する。
assert lib.assertMsg (rejects "fd7a:115c:a1e0:100::11") "別のプレフィックスを通しました";
toAddress4
