{ pkgs, ... }:
{
  services = {
    xserver = {
      # 何かあったときの復旧用のミニマルなウィンドウマネージャを有効にしておきます。
      windowManager.icewm.enable = true;
    };
  };
  # 復旧に必要な最低限のパッケージをインストールしておきます。
  environment.systemPackages = with pkgs; [
    rxvt-unicode
    xterm
  ];
}
