{ config, ... }:
let
  tailscale = config.services.tailscale.package;
in
{
  # Exit Nodeとして動作するための追加設定。
  # 基本的なTailscale有効化は nixos/core/tailscale.nix で行っています。
  services.tailscale = {
    openFirewall = true;
    useRoutingFeatures = "both";
  };

  # Tailscale Funnelでサーバをパブリックインターネットに公開する設定。
  # [ncaq/infra.ncaq.net: Infrastructure as Code for ncaq.net](https://github.com/ncaq/infra.ncaq.net/)
  # でFunnelを有効化しています。
  systemd.services.tailscale-funnel = {
    description = "Configure Tailscale Funnel";
    requires = [
      "tailscaled.service"
      "caddy.service"
    ];
    after = [
      "tailscaled.service"
      "caddy.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${tailscale}/bin/tailscale funnel --bg http://127.0.0.1:8080";
      ExecStop = "${tailscale}/bin/tailscale funnel --bg off";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # IP転送を有効化。
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
