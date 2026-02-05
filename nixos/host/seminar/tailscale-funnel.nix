# Tailscale Funnelでサーバをパブリックインターネットに公開する設定。
# [ncaq/infra.ncaq.net: Infrastructure as Code for ncaq.net](https://github.com/ncaq/infra.ncaq.net/)
# でFunnelを有効化しています。
{ config, ... }:
let
  tailscale = config.services.tailscale.package;
  domain = "seminar.border-saurolophus.ts.net";
  certDir = "/var/lib/tailscale-cert";
  certFile = "${certDir}/${domain}.crt";
  keyFile = "${certDir}/${domain}.key";
in
{
  # Funnel設定(パブリックインターネットからのアクセス用)。
  systemd.services.tailscale-funnel = {
    description = "Configure Tailscale Funnel for attic cache";
    wants = [
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
      RemainAfterExit = true;
      ExecStart = "${tailscale}/bin/tailscale funnel --bg http://127.0.0.1:8081";
      ExecStop = "${tailscale}/bin/tailscale funnel --bg off";
    };
  };

  # Tailscaleドメイン用のTLS証明書を取得・更新するサービス。
  # Caddyがtailnet内からのアクセスでもTLSを提供できるようにします。
  systemd.tmpfiles.rules = [
    "d ${certDir} 0750 caddy caddy -"
  ];
  systemd.services.tailscale-cert = {
    description = "Generate Tailscale TLS certificates for Caddy";
    wants = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${tailscale}/bin/tailscale cert --cert-file ${certFile} --key-file ${keyFile} ${domain}";
      ExecStartPost = "+/run/current-system/systemd/bin/systemctl reload caddy";
      User = "caddy";
      Group = "caddy";
    };
  };
  systemd.timers.tailscale-cert = {
    description = "Weekly renewal of Tailscale TLS certificates";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
