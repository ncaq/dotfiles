{ config, ... }:
let
  # 各WiFiプロファイル共通の構造を生成するヘルパー。
  # idとssid, key-mgmt, secretのsopsキーを受け取り、
  # ensureProfilesに渡せるattrsetを返す。
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
        # psk値はnm-file-secret-agent経由でランタイムに注入する。
        # `psk-flags=1`はagent-ownedを意味しNMが秘密値をsecret agentに問い合わせる。
        psk = "";
        psk-flags = "1";
      };
      ipv4 = {
        method = "auto";
      };
      ipv6 = {
        addr-gen-mode = "default";
        method = "auto";
      };
    };

  # nm-file-secret-agentにpsk値を渡すエントリを生成するヘルパー。
  mkSecretEntry = id: {
    matchId = id;
    matchType = "wifi";
    matchSetting = "802-11-wireless-security";
    key = "psk";
    file = config.sops.secrets."wifi/${id}".path;
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

    secrets.entries = map (w: mkSecretEntry w.id) wifiNetworks;
  };

  sops.secrets = builtins.listToAttrs (
    map (w: {
      name = "wifi/${w.id}";
      value = {
        sopsFile = ../../secrets/wifi.yaml;
        key = w.id;
      };
    }) wifiNetworks
  );
}
