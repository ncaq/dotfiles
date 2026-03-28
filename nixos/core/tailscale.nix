{
  pkgs,
  lib,
  config,
  ...
}:
{
  services.tailscale = {
    enable = true;
    # ベースとなる設定。
    useRoutingFeatures = lib.mkDefault "client";
  };

  systemd.services.tailscale-online = {
    description =
      "Wait for Tailscale to be online"
      + " - absorbs the delay between tailscaled.service startup and tailnet connection establishment";
    bindsTo = [ "tailscaled.service" ];
    wants = [ "network-online.target" ];
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
            tailscale status --peers=false > /dev/null 2>&1
          '';
        }
      );
      Restart = "on-failure";
      RestartSec = "1s";
      RestartSteps = 20;
      RestartMaxDelaySec = "60s";
    };
    unitConfig = {
      StartLimitIntervalSec = "10min";
      StartLimitBurst = 20;
    };
  };
}
