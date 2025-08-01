{ pkgs, ... }:
{
  # デスクトップマシンでは画面の自動オフを無効にする。
  systemd.user.services.dpms-disable = {
    description = "Disable DPMS (Display Power Management Signaling)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "dpms-disable" ''
        set -euo pipefail
        # DPMSを無効化
        ${pkgs.xorg.xset}/bin/xset -dpms
        # スクリーンセーバーも無効化
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
