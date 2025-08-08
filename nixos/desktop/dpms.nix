{ pkgs, ... }:
{
  # OLEDモニターにも対応したDPMS設定。
  # 作業の邪魔にならない程度に管理。
  systemd.user.services.dpms-oled = {
    description = "Configure DPMS for OLED monitors";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "dpms-oled" ''
        set -euo pipefail
        # DPMSを有効化
        ${pkgs.xorg.xset}/bin/xset +dpms
        # DPMS設定 (スタンバイ:30分, サスペンド:45分, オフ:60分)
        ${pkgs.xorg.xset}/bin/xset dpms 1800 2700 3600
        # スクリーンセーバーは使わずDPMSに任せます
        ${pkgs.xorg.xset}/bin/xset s off
      '';
      Environment = [
        "DISPLAY=:0"
      ];
      Restart = "on-failure";
      RestartSec = "5s";
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
