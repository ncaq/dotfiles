/**
  NixOS Containerのvethへ、
  ホスト側からアドレスとルートを設定する定義を生成する関数。

  何も宣言しないとsystemdに同梱の`80-container-ve.network`が適用されて、
  link localアドレスと動的な/28がvethに乗る。
  `hostAddress`は/32でしか乗らないため、
  コンテナ宛の送信元アドレスがlink local側から選ばれてしまい、
  コンテナ側で`hostAddress`からの接続だけを許可しているルールにマッチしない。

  NixOSコンテナモジュールのExecStartPostはコンテナのdefault target到達後に実行されるため、
  コンテナ内のサービスが起動する時点ではホスト側のネットワーク設定が終わっていない。
  ネットワークを必要とするサービスがコンテナ内にあるとデッドロックする。
  systemd-networkdはvethの作成直後に設定を適用するのでこの順序問題も起きない。

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
  - `addr`: `host`と`guest`を持つアドレスの組。
    `machineAddresses`の同名エントリをそのまま渡す
*/
{
  lib,
  name,
  addr,
}:
{
  services."container@${name}".postStart = lib.mkForce ''
    ifaceHost=ve-$INSTANCE
    ip link set dev "$ifaceHost" up
    ip addr add ${addr.host} dev "$ifaceHost" 2>/dev/null || true
    ip route add ${addr.guest} dev "$ifaceHost" 2>/dev/null || true
  '';
  # Linuxのインターフェース名はIFNAMSIZ(15文字)制限があるため、
  # 実際のインターフェース名は`ve-github-rRhHH`のように短縮されることがある。
  # しかしsystemd-networkdの`matchConfig.Name`はaltname(代替名)もマッチするため、
  # コンテナ名から生成される完全な名前で正しくマッチする。
  network.networks."20-${name}-veth" = {
    matchConfig.Name = "ve-${name}";
    addresses = [ { Address = "${addr.host}/32"; } ];
    routes = [ { Destination = "${addr.guest}/32"; } ];
  };
}
