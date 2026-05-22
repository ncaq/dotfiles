{ lib, config, ... }:
let
  # WiFiのpsk値を渡す環境変数名を生成する。
  # systemdの`EnvironmentFile`経由で、
  # NetworkManager-ensure-profilesに渡され、
  # envsubstでkeyfileに展開される。
  # 環境変数名にはハイフンを使えないためアンダースコアに変換し大文字化する。
  pskEnvName = id: "WIFI_${lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] id)}_PSK";

  # 各WiFiプロファイル共通の構造を生成するヘルパー。
  # 各種引数から`ensureProfiles`に渡せるattrsetを返す。
  # interface-nameは敢えて指定せず、
  # どのWiFiインターフェースでも使えるようにする。
  mkWifi =
    {
      id,
      uuid,
      ssid,
      keyMgmt,
    }:
    {
      connection = {
        inherit id uuid;
        type = "wifi";
      };
      wifi = {
        mode = "infrastructure";
        inherit ssid;
      };
      wifi-security = {
        key-mgmt = keyMgmt;
        # psk値は`environmentFiles`経由でenvsubstがkeyfileに展開する。
        # `psk-flags`は指定せず(=`0`, system-owned)、
        # NetworkManager本体がkeyfileのpskを直接管理する。
        # secret agentを介さないため手動接続でもパスワード入力を求められない。
        # keyfileは`/run/NetworkManager/system-connections/`(tmpfs, root専用0600)に生成され、
        # Nixストアにpsk平文が残ることはない。
        psk = "\${${pskEnvName id}}";
      };
      ipv4 = {
        method = "auto";
      };
      ipv6 = {
        addr-gen-mode = "default";
        method = "auto";
      };
    };

  wifiNetworks = [
    {
      id = "diana";
      uuid = "b983e52d-f3a4-4c2d-b04e-2be1723b0d45";
      ssid = "diana";
      keyMgmt = "sae";
    }
    {
      id = "hermes";
      uuid = "0c58734d-a746-49d2-87c6-2693ee48df8a";
      ssid = "hermes";
      keyMgmt = "sae";
    }
    {
      id = "lacey-wifi";
      uuid = "8c03253a-7533-4332-9b20-c8057849c55f";
      ssid = "Lacey WiFi";
      keyMgmt = "wpa-psk";
    }
    {
      id = "pluszero-guest";
      uuid = "aa0eed8a-aa3f-4f28-95d4-34757e194d77";
      ssid = "pluszero-guest";
      keyMgmt = "wpa-psk";
    }
  ];
in
{
  networking.networkmanager.ensureProfiles = {
    profiles = builtins.listToAttrs (
      map (w: {
        name = w.id;
        value = mkWifi w;
      }) wifiNetworks
    );
    # 各WiFiのpsk値を環境変数として渡すenvファイル。
    # `sops.templates`がplaceholderを実値に展開した上でroot専用ファイルとして配置する。
    # NetworkManagerの通常の手動セットアップの場合、
    # `/etc/NetworkManager/system-connections/`に、
    # パスワードを含めた平文ファイルが生成されるので、
    # セキュリティに大した差はない。
    # 永続領域に置かれないだけ少しだけ安全かもしれない。
    environmentFiles = [ config.sops.templates."wifi-env".path ];
  };

  sops = {
    # `KEY=value`形式のenvファイルを生成し`ensureProfiles.environmentFiles`に渡す。
    templates."wifi-env".content = lib.concatMapStringsSep "\n" (
      w: "${pskEnvName w.id}=${config.sops.placeholder."wifi/${w.id}"}"
    ) wifiNetworks;
    secrets = builtins.listToAttrs (
      map (w: {
        name = "wifi/${w.id}";
        value = {
          sopsFile = ../../secrets/wifi.yaml;
          key = w.id;
        };
      }) wifiNetworks
    );
  };

  # `NetworkManager-ensure-profiles.service`は、
  # `environmentFiles`に指定したsopsテンプレート(`/run/secrets/rendered/wifi-env`)を、
  # 必須の`EnvironmentFile`として読み込む。
  # このファイルを展開するのは`sops-install-secrets.service`だが、
  # nixpkgs本体の定義には両者の順序依存がなく、
  # tmpfs上のファイルは毎ブート再生成が必要なため、
  # 展開前に`ensure-profiles`が走ると`Failed to load environment files`で失敗することがある。
  # 明示的に`sops-install-secrets.service`の後に走るよう順序付けする。
  systemd.services.NetworkManager-ensure-profiles = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };
}
