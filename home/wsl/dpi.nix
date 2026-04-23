{ pkgs, lib, ... }:
{
  systemd.user.services.wsl-set-xorg-dpi = {
    Unit = {
      Description = "Set DPI for WSLg xorg environment";
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = lib.getExe (
        pkgs.writeShellApplication {
          name = "wsl-set-xorg-dpi-wait-start-server";
          runtimeInputs = with pkgs; [
            coreutils
            xorg.xset
          ];
          text = ''
            for _ in $(seq 10); do
              if [ -S /tmp/.X11-unix/X0 ] && xset q &>/dev/null; then
                exit 0
              fi
              sleep 1
            done
            echo "Timed out waiting for X server" >&2
            exit 1
          '';
        }
      );
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "wsl-set-xorg-dpi";
          runtimeInputs = with pkgs; [
            xorg.xrandr
            xorg.xrdb
          ];
          text = ''
            DPI="''${WSL_DPI:-144}"
            xrandr --dpi "$DPI"
            echo "Xft.dpi: $DPI" | xrdb -merge
          '';
        }
      );
      Environment = [
        "DISPLAY=:0"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
