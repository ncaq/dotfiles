{ pkgs, lib, ... }:
{
  systemd = {
    # 画面ロックまでの時間を30分に設定。
    # xss-lockはXのスクリーンセーバータイムアウトをトリガーにするため、
    # xsetでタイムアウトを設定します。
    # デスクトップPCではdpms.nixで`xset s off`していますが、
    # ラップトップでは適度なタイムアウトを設定します。
    user.services.screensaver-timeout = {
      description = "Set X screensaver timeout";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.xorg.xset}/bin/xset s 1800 1800";
        Environment = [ "DISPLAY=:0" ];
        Restart = "on-failure";
        RestartSec = "5s";
      };
      wantedBy = [ "graphical-session.target" ];
    };
    # 蓋を閉じたときは即時サスペンドせず、
    # 5分後にロックしてからサスペンド。
    # 移動中にすぐ開くケースに対応するための猶予。
    services.lid-close-lock = {
      description = "Lock screen and suspend after lid close delay";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "lid-close-lock-and-suspend";
            runtimeInputs = with pkgs; [
              coreutils
              systemd
            ];
            # xss-lockがsleep inhibitor lockを取得するため、
            # ロッカーが起動するまでsuspendはブロックされます。
            # 念のためsleepも挟んでいます。
            text = ''
              loginctl lock-sessions
              sleep 1
              systemctl suspend
            '';
          }
        );
      };
    };
    timers.lid-close-lock = {
      description = "5-minute delay before locking on lid close";
      timerConfig = {
        OnActiveSec = "5min";
      };
    };
  };
  services = {
    # デフォルトの蓋を閉じたときの動作を無効化。
    logind.settings.Login.HandleLidSwitch = "ignore";
    acpid = {
      enable = true;
      # 蓋の開閉イベントでロックタイマーを制御。
      lidEventCommands = ''
        case "$1" in
          *close)
            ${pkgs.systemd}/bin/systemctl start lid-close-lock.timer
            ;;
          *open)
            ${pkgs.systemd}/bin/systemctl stop lid-close-lock.timer 2>/dev/null || true
            ;;
        esac
      '';
    };
  };
}
