/**
  NixOS Containerのvethへ、
  ホスト側からアドレスとルートを設定する定義を生成する関数。

  NixOSコンテナモジュールのExecStartPostはコンテナのdefault target到達後に実行されるため、
  コンテナ内のサービスが起動する時点ではホスト側のネットワーク設定が終わっていない。
  ネットワークを必要とするサービスがコンテナ内にあるとデッドロックする。
  systemd-networkdはvethの作成直後に設定を適用するのでこの順序問題も起きない。
  ここで宣言する`.network`が先に一致するので、
  systemdに同梱の`80-container-ve.network`はこのvethには使われない。

  NixOSコンテナモジュールが生成する`postStart`は`ip addr add`と`ip route add`を使うため、
  systemd-networkdが先に設定済みだとEEXISTで失敗する。
  実際の設定はsystemd-networkdへ任せるので、冪等にして失敗を無視する。

  `systemd`へマージできる`{ services, network }`を返す。

  ```nix
  systemd = lib.mkMerge [
    (import ../../lib/container-veth.nix {
      inherit lib;
      name = "open-webui";
      addr = config.machineAddresses.open-webui;
    })
    { tmpfiles.rules = [ ... ]; }
  ];
  ```

  # 引数

  - `lib`: `mkForce`と末尾の`assert`に使う
  - `name`: 対象のコンテナ名。
    vethのインタフェース名とユニット名の両方を導く
  - `addr`: IPv6の`host6`と`guest6`、IPv4の`host4`と`guest4`を持つアドレスの組。
    IPv4を持たないマシンでは`host4`と`guest4`は`null`で、IPv4の設定を出さない。
    `machineAddresses`の同名エントリをそのまま渡す
*/
{
  lib,
  name,
  addr,
}:
let
  veth =
    name: addr:
    let
      hasIpv4 = addr.guest4 != null;
    in
    {
      services."container@${name}".postStart = lib.mkForce (
        ''
          ifaceHost=ve-$INSTANCE
          ip link set dev "$ifaceHost" up
          ip -6 addr add ${addr.host6} dev "$ifaceHost" 2>/dev/null || true
          ip -6 route add ${addr.guest6} dev "$ifaceHost" 2>/dev/null || true
        ''
        + lib.optionalString hasIpv4 ''
          ip addr add ${addr.host4} dev "$ifaceHost" 2>/dev/null || true
          ip route add ${addr.guest4} dev "$ifaceHost" 2>/dev/null || true
        ''
      );
      # Linuxのインタフェース名はIFNAMSIZ(15文字)制限があるため、
      # 実際のインタフェース名は`ve-github-rRhHH`のように短縮されることがある。
      # しかしsystemd-networkdの`matchConfig.Name`はaltname(代替名)もマッチするため、
      # コンテナ名から生成される完全な名前で正しくマッチする。
      network.networks."20-${name}-veth" = {
        matchConfig.Name = "ve-${name}";
        addresses = [
          { Address = "${addr.host6}/128"; }
        ]
        ++ lib.optional hasIpv4 { Address = "${addr.host4}/32"; };
        routes = [
          { Destination = "${addr.guest6}/128"; }
        ]
        ++ lib.optional hasIpv4 { Destination = "${addr.guest4}/32"; };
      };
    };

  # 以下は末尾の`assert`のための入力。
  dualAddr = {
    host6 = "fdf2:a855:5a3f:100::90";
    guest6 = "fdf2:a855:5a3f:100::91";
    host4 = "192.168.100.90";
    guest4 = "192.168.100.91";
  };
  dual = veth "test" dualAddr;
  ipv6Only = veth "test" (
    dualAddr
    // {
      host4 = null;
      guest4 = null;
    }
  );
  networkOf = v: v.network.networks."20-test-veth";
  # `mkForce`で包んでいるので中身を取り出す。
  postStartOf = v: v.services."container@test".postStart.content;
in
# IPv4を持つコンテナにはIPv6とIPv4の両方を、
# 持たないコンテナにはIPv6だけを設定することを確かめる。
#
# systemd-networkdの設定とpostStartの`ip`のコマンドの両方で出し分けているので、
# 条件を取り違えると、
# IPv4を持たないコンテナに`null`を渡す`ip`のコマンドが入ったり、
# IPv4を持つコンテナからIPv4が抜けたりする。
# どちらも評価は通るので、実機でコンテナを起動するまで気付けない。
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
veth name addr
