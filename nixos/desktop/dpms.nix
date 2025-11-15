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
        # スクリーンセーバーの方は無効化
        ${pkgs.xorg.xset}/bin/xset s off
        # DPMSを有効化
        ${pkgs.xorg.xset}/bin/xset +dpms
        # DPMS設定 (スタンバイ:120分, サスペンド:240分, オフ:240分)
        ${pkgs.xorg.xset}/bin/xset dpms 7200 14400 14400
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
