{ pkgs, lib, ... }:
{
  # OLEDモニターにも対応したDPMS設定。
  # 作業の邪魔にならない程度に管理。
  systemd.user.services.dpms-oled = {
    description = "Configure DPMS for OLED monitors";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "dpms-oled";
          runtimeInputs = with pkgs; [ xorg.xset ];
          text = ''
            # スクリーンセーバーの方は無効化
            xset s off
            # DPMSを有効化
            xset +dpms
            # DPMS設定 (スタンバイ:6時間, サスペンド:7時間, オフ:8時間)
            xset dpms 21600 25200 28800
          '';
        }
      );
      Restart = "on-failure";
      RestartSec = "5s";
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
