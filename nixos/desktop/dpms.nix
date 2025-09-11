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
        # DPMS設定 (スタンバイ:60分, サスペンド:100分, オフ:120分)
        ${pkgs.xorg.xset}/bin/xset dpms 3600 6000 7200
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
