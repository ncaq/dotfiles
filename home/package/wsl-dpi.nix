{
  pkgs,
  lib,
  isWSL,
  ...
}:
lib.mkIf isWSL {
  systemd.user.services.wsl-dpi = {
    Unit = {
      Description = "Set DPI for WSLg environment";
    };
    Service = {
      Type = "oneshot";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.writeScript "wsl-set-dpi-wait-xorg" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        timeout=10
        while [ $timeout -gt 0 ]; do
          if [ -S /tmp/.X11-unix/X0 ] && ${pkgs.xorg.xset}/bin/xset q &>/dev/null; then
            break
          fi
          ${pkgs.coreutils}/bin/sleep 1
          timeout=$((timeout - 1))
        done
      ''}'";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.writeScript "wsl-set-dpi" ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        DPI=''${WSL_DPI:-144}
        ${pkgs.xorg.xrandr}/bin/xrandr --dpi "$DPI"
        echo "Xft.dpi: $DPI"|${pkgs.xorg.xrdb}/bin/xrdb -merge
      ''}'";
      Environment = [
        "DISPLAY=:0"
      ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
