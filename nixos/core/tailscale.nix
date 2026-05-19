{
  pkgs,
  lib,
  config,
  ...
}:
{
  services.tailscale = {
    enable = true;
  };

  systemd.services.tailscale-online = {
    description = "Wait for Tailscale tailnet connection to be established";
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "wait-for-tailscale";
          runtimeInputs = [ config.services.tailscale.package ];
          text = ''
            until tailscale status --peers=false > /dev/null 2>&1; do
              sleep 1
            done
          '';
        }
      );
      TimeoutStartSec = "10min";
    };
  };
}
