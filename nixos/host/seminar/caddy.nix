{
  config,
  ...
}:
let
  atticdAddr = config.containerAddresses.atticd.container;
  tailscale = config.services.tailscale.package;
  tailscaleDomain = "seminar.border-saurolophus.ts.net";
  certDir = "/var/lib/tailscale-cert";
  certFile = "${certDir}/${tailscaleDomain}.crt";
  keyFile = "${certDir}/${tailscaleDomain}.key";
in
{
  sops.secrets."cloudflare-dns-api-token" = {
    sopsFile = ../../../secrets/seminar/caddy.yaml;
    key = "cloudflare_dns_api_token";
    owner = "caddy";
    group = "caddy";
    mode = "0400";
  };

  services.caddy = {
    enable = true;
    email = "ncaq@ncaq.net";
    # tailnet内からのアクセス用。
    # 分かり易さのためCaddyがまとめてリクエストを管理します。
    virtualHosts."${tailscaleDomain}".extraConfig = ''
      tls ${certFile} ${keyFile}
      handle_path /nix/cache/* {
        reverse_proxy http://${atticdAddr}:8080
      }
      redir /nix/cache /nix/cache/
    '';
    # Tailscale Funnelからのリクエストを受けるリバースプロキシ。
    # Tailscale Funnelはlocalhostへの転送しかサポートしていないため、
    # コンテナへの転送をするためにCaddyでプロキシします。
    virtualHosts.":8080".extraConfig = ''
      bind 127.0.0.1
      handle_path /nix/cache/* {
        reverse_proxy http://${atticdAddr}:8080
      }
      redir /nix/cache /nix/cache/
    '';
  };

  # Tailscaleドメイン用のTLS証明書を取得・更新するサービス。
  # Caddyがtailnet内からのアクセスでもTLSを提供できるようにします。
  systemd.tmpfiles.rules = [
    "d ${certDir} 0750 caddy caddy -"
  ];
  systemd.services.tailscale-cert-for-caddy = {
    description = "Generate Tailscale TLS certificates for Caddy";
    requires = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${tailscale}/bin/tailscale cert --cert-file ${certFile} --key-file ${keyFile} ${tailscaleDomain}";
      RemainAfterExit = true;
      User = "caddy";
      Group = "caddy";
    };
  };
  systemd.timers.tailscale-cert-for-caddy = {
    description = "Weekly renewal of Tailscale TLS certificates";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

  systemd.services.caddy = {
    wants = [ "tailscale-cert-for-caddy.service" ];
    after = [ "tailscale-cert-for-caddy.service" ];
  };
}
