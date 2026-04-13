{ pkgs, ... }:
let
  acTimeout = 30 * 60; # AC電源時: 30分
  battTimeout = 15 * 60; # バッテリー時: 15分
in
{
  systemd.user.services.dpms-power = {
    description = "Adjust DPMS timeout based on AC/battery state";
    serviceConfig = {
      ExecStart = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "dpms-power";
          runtimeInputs = with pkgs; [
            gnugrep
            upower
            xorg.xset
          ];
          text = ''
            set_dpms() {
              if upower -i /org/freedesktop/UPower | grep -q "on-battery:.*yes"; then
                xset dpms ${toString battTimeout} ${toString battTimeout} ${toString battTimeout}
              else
                xset dpms ${toString acTimeout} ${toString acTimeout} ${toString acTimeout}
              fi
            }
            # Set initial state
            set_dpms
            # Monitor for power state changes
            upower --monitor | while read -r _line; do
              set_dpms
            done
          '';
        }
      );
      Restart = "on-failure";
      RestartSec = "10s";
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
