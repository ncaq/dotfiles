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

  # Tailscale Funnel/Serveの設定。
  # [ncaq/infra.ncaq.net: Infrastructure as Code for ncaq.net](https://github.com/ncaq/infra.ncaq.net/)
  # でFunnelを有効化しています。
  systemd.services = {
    # Funnelはパブリックインターネットに公開する。
    # Caddy :8080がパス毎に公開サービスをルーティングする。
    tailscale-funnel = {
      description = "Configure Tailscale Funnel";
      requires = [
        "caddy.service"
        "tailscaled.service"
      ];
      after = [
        "caddy.service"
        "tailscaled.service"
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
    # Serveはtailnet内のみに公開する(Funnelではない)。
    # Caddy :8081がパス毎にtailnet専用サービスをルーティングする。
    tailscale-serve = {
      description = "Configure Tailscale Serve";
      requires = [
        "caddy.service"
        "tailscaled.service"
      ];
      after = [
        "caddy.service"
        "tailscaled.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tailscale}/bin/tailscale serve --bg --https=8443 http://127.0.0.1:8081";
        ExecStop = "${tailscale}/bin/tailscale serve --https=8443 off";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };

  # IP転送を有効化。
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
