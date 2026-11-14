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
  hasIpv4 = addr.guest4 != null;
  ipv4 = list: if hasIpv4 then list else [ ];
  publicDns = import ./public-dns.nix;
  dns = map (server: server.address) (publicDns.ipv6 ++ ipv4 publicDns.ipv4);
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
}
