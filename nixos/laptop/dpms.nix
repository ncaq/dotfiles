{ pkgs, ... }:
let
  # AC電源時: 30.5分。
  # スクリーンセーバーのタイムアウト(screen-lock-time.nixで30分)より後にすることで、
  # ロックの起点が常にxss-lockのnotifier経由になり猶予時間が機能します。
  acTimeout = 30 * 60 + 30;
  # バッテリー時: 15分。
  # 省電力を優先してスクリーンセーバーのタイムアウトより先に消灯させます。
  battTimeout = 15 * 60;
in
{
  systemd.user.services.dpms-timeout = {
    description = "Configure screen saver and DPMS timeout";
    serviceConfig = {
      ExecStart = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "dpms-timeout";
          runtimeInputs = with pkgs; [
            gnugrep
            upower
            xset
          ];
          text = ''
            # 頻繁なxset呼び出しを避けるため、状態が変わったときのみDPMSを更新する。
            current_state=""
            set_dpms() {
              if upower -i /org/freedesktop/UPower | grep -q "on-battery:.*yes"; then
                new_state="battery"
              else
                new_state="ac"
              fi
              if [ "$new_state" != "$current_state" ]; then
                current_state="$new_state"
                if [ "$current_state" == "battery" ]; then
                  xset dpms ${toString battTimeout} ${toString battTimeout} ${toString battTimeout}
                else
                  xset dpms ${toString acTimeout} ${toString acTimeout} ${toString acTimeout}
                fi
              fi
            }
            # Set initial state
            set_dpms
            # Monitor for power state changes
            upower --monitor | grep "battery" | while read -r _line; do
              set_dpms
            done
          '';
        }
      );
      Restart = "always";
      RestartSec = "10s";
    };
    wantedBy = [ "graphical-session.target" ];
  };
  # upower CLIが接続するD-Busサービスを提供。
  # 無効だとupowerコマンドがcoredumpする。
  services.upower.enable = true;
}
