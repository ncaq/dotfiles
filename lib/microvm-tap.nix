/**
  microVMのTAPインターフェイスに、
  ホスト側とゲスト側の両方からアドレスとルートを設定する定義を生成する関数。

  microvm.nixの推奨に従い、
  どちらもsystemd-networkdで設定する。
  `networking.interfaces`が生成する`network-addresses-*`サービスは、
  `network.target`より前に順序付けられるため、
  `network.target`より後に作成されるTAPインターフェイスと相性が悪い。

  ホストとゲストはTAPで1対1に繋がるだけなので、
  ホスト側は/128のアドレスにゲストへのルートを足す。
  ゲスト側はホストをゲートウェイにして、
  名前解決は`lib/public-dns.nix`の公開DNSへ投げる。
  ゲストの出口はホストの`local.machineEgress`で絞るので、
  LANのDNSは使わせない。

  IPv4は`addr`がIPv4のアドレスを持つ時だけ同じ形で足す。
  持たせる基準は`lib/machine-address4.nix`に書いてある。
  IPv4を持たないゲストからはIPv4の公開DNSにも届かないので、それも外す。

  `host`は`systemd.network.networks`へマージできる属性セットを、
  `guest`はゲストの`systemd.network`にそのまま渡せる属性セットを返す。

  ```nix
  let
    tapNetwork = import ../../../lib/microvm-tap.nix {
      tap = "vm-mcp-nixos";
      addr = config.machineAddresses.mcp-nixos;
    };
  in
  {
    microvm.vms.mcp-nixos.config.systemd.network = tapNetwork.guest;
    systemd.network.networks = tapNetwork.host;
  }
  ```

  # 引数

  - `tap`: ホスト側のTAPインターフェイス名。
    VMの`microvm.interfaces`の`id`と同じ名前を渡す
  - `addr`: IPv6の`host6`と`guest6`、IPv4の`host4`と`guest4`を持つアドレスの組。
    IPv4を持たないマシンでは`host4`と`guest4`は`null`。
    `machineAddresses`の同名エントリをそのまま渡す
*/
{
  tap,
  addr,
}:
let
  publicDns = import ./public-dns.nix;
  addresses = map (server: server.address);

  network =
    tap: addr:
    let
      hasIpv4 = addr.guest4 != null;
      ipv4 = list: if hasIpv4 then list else [ ];
      dns = addresses (publicDns.ipv6 ++ ipv4 publicDns.ipv4);
    in
    {
      host."20-${tap}" = {
        matchConfig.Name = tap;
        addresses = [
          { Address = "${addr.host6}/128"; }
        ]
        ++ ipv4 [ { Address = "${addr.host4}/32"; } ];
        routes = [
          { Destination = "${addr.guest6}/128"; }
        ]
        ++ ipv4 [ { Destination = "${addr.guest4}/32"; } ];
      };
      guest = {
        enable = true;
        networks."20-lan" = {
          matchConfig.Type = "ether";
          networkConfig = {
            Address = [ "${addr.guest6}/64" ] ++ ipv4 [ "${addr.guest4}/24" ];
            Gateway = [ addr.host6 ] ++ ipv4 [ addr.host4 ];
            DNS = dns;
          };
        };
      };
    };

  # 以下は末尾の`assert`のための入力。
  dualAddr = {
    host6 = "fdf2:a855:5a3f:100::30";
    guest6 = "fdf2:a855:5a3f:100::31";
    host4 = "192.168.100.30";
    guest4 = "192.168.100.31";
  };
  dual = network "vm-test" dualAddr;
  ipv6Only = network "vm-test" (
    dualAddr
    // {
      host4 = null;
      guest4 = null;
    }
  );
  guestConfig = n: n.guest.networks."20-lan".networkConfig;
  hostOf = n: n.host."20-vm-test";
in
# IPv4を持つマシンにはIPv6とIPv4の両方を、
# 持たないマシンにはIPv6だけを設定することを確かめる。
#
# IPv4を持つかどうかで出し分けているので、
# 条件を取り違えると、
# IPv4を持たないゲストに`null/24`のような壊れた値やIPv4のDNSが入ったり、
# IPv4を持つゲストからIPv4が抜けたりする。
# どちらも評価は通るので、実機でVMを起動するまで気付けない。
# `lib`を受け取らないファイルなので、メッセージは`throw`で出す。
assert
  (guestConfig dual).Address == [
    "fdf2:a855:5a3f:100::31/64"
    "192.168.100.31/24"
  ]
  || throw "IPv4を持つゲストのアドレスが違います";
assert
  (guestConfig dual).Gateway == [
    "fdf2:a855:5a3f:100::30"
    "192.168.100.30"
  ]
  || throw "IPv4を持つゲストのゲートウェイが違います";
assert
  (guestConfig dual).DNS == addresses publicDns.ipv6 ++ addresses publicDns.ipv4
  || throw "IPv4を持つゲストのDNSがIPv6を先にした両方になっていません";
assert
  (hostOf dual).addresses == [
    { Address = "fdf2:a855:5a3f:100::30/128"; }
    { Address = "192.168.100.30/32"; }
  ]
  || throw "IPv4を持つマシンのホスト側のアドレスが違います";
assert
  (hostOf dual).routes == [
    { Destination = "fdf2:a855:5a3f:100::31/128"; }
    { Destination = "192.168.100.31/32"; }
  ]
  || throw "IPv4を持つマシンのホスト側の経路が違います";
assert
  (guestConfig ipv6Only).Address == [ "fdf2:a855:5a3f:100::31/64" ] || throw "IPv4を持たないゲストのアドレスが違います";
assert
  (guestConfig ipv6Only).Gateway == [ "fdf2:a855:5a3f:100::30" ] || throw "IPv4を持たないゲストのゲートウェイが違います";
assert
  (guestConfig ipv6Only).DNS == addresses publicDns.ipv6 || throw "IPv4を持たないゲストにIPv6以外のDNSがあります";
assert
  (hostOf ipv6Only).addresses == [ { Address = "fdf2:a855:5a3f:100::30/128"; } ]
  || throw "IPv4を持たないマシンのホスト側のアドレスが違います";
assert
  (hostOf ipv6Only).routes == [ { Destination = "fdf2:a855:5a3f:100::31/128"; } ]
  || throw "IPv4を持たないマシンのホスト側の経路が違います";
# 個別の値を見落としても、`null`が値や文字列に紛れ込めばここで分かる。
assert
  builtins.match ".*null.*" (builtins.toJSON ipv6Only) == null
  || throw "IPv4を持たないマシンの設定に`null`が紛れ込んでいます";
network tap addr
