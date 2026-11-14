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

  - `lib`: `mkForce`に使う
  - `name`: 対象のコンテナ名。
    vethのインターフェース名とユニット名の両方を導く
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
  # Linuxのインターフェース名はIFNAMSIZ(15文字)制限があるため、
  # 実際のインターフェース名は`ve-github-rRhHH`のように短縮されることがある。
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
}
