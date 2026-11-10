{
  pkgs,
  lib,
  config,
  ...
}:
let
  # 有線(Ethernet)接続中はWiFiの接続だけを切り、
  # WiFiラジオはオンのまま維持する。
  # NetworkManagerのdispatcherスクリプトとして、
  # デバイスの`up`/`down`イベントごとに呼ばれる。
  #
  # 中身は`pkgs/wifi-wired-exclusive`にある。
  wifiWiredExclusive = pkgs.callPackage ../../pkgs/wifi-wired-exclusive {
    networkmanager = config.networking.networkmanager.package;
  };
in
{
  networking.networkmanager.dispatcherScripts = [
    {
      source = lib.getExe wifiWiredExclusive;
      type = "basic";
    }
  ];
}
