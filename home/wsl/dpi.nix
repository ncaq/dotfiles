{ pkgs, lib, ... }:
{
  systemd.user.services.wsl-dpi = {
    Unit = {
      Description = "Set DPI for WSLg environment";
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = lib.getExe (
        pkgs.writeShellApplication {
          name = "wsl-set-dpi-wait-xorg";
          runtimeInputs = with pkgs; [
            coreutils
            xorg.xset
          ];
          text = ''
            timeout=10
            while [ "$timeout" -gt 0 ]; do
              if [ -S /tmp/.X11-unix/X0 ] && xset q &>/dev/null; then
                break
              fi
              sleep 1
              timeout=$((timeout - 1))
            done
          '';
        }
      );
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "wsl-set-dpi";
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
