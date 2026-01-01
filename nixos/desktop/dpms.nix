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
        # DPMS設定 (スタンバイ:6時間, サスペンド:7時間, オフ:8時間)
        ${pkgs.xorg.xset}/bin/xset dpms 21600 25200 28800
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
