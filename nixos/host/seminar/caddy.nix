{
  pkgs,
  config,
  ...
}:
let
  atticdAddr = config.containerAddresses.atticd.container;
  tailscaleDomain = "seminar.border-saurolophus.ts.net";
  certDir = "/var/lib/tailscale-cert";
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
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
      hash = "sha256-dnhEjopeA0UiI+XVYHYpsjcEI6Y1Hacbi28hVKYQURg=";
    };
    virtualHosts."cache.nix.ncaq.net".extraConfig = ''
      tls {
        dns cloudflare {file.${config.sops.secrets."cloudflare-dns-api-token".path}}
      }
      reverse_proxy http://${atticdAddr}:8080
    '';
    # Tailscale Funnelからのリクエストを受けるリバースプロキシ。
    # Tailscale Funnelはlocalhostへの転送しかサポートしていないため、
    # コンテナへの転送をするためにCaddyでプロキシします。
    # パス処理はtailnet用virtual hostと同じロジックです。
    virtualHosts.":8081".extraConfig = ''
      bind 127.0.0.1
      handle_path /nix/cache/* {
        reverse_proxy http://${atticdAddr}:8080
      }
      redir /nix/cache /nix/cache/
    '';
    # tailnet内からのアクセス用。
    # Caddyが`*:443`を占有しているため、tailscaledではなくCaddyが、
    # Tailscaleドメインの`/nix/cache/`をSNIベースで処理します。
    virtualHosts."${tailscaleDomain}".extraConfig = ''
      tls ${certDir}/${tailscaleDomain}.crt ${certDir}/${tailscaleDomain}.key
      handle_path /nix/cache/* {
        reverse_proxy http://${atticdAddr}:8080
      }
      redir /nix/cache /nix/cache/
    '';
  };
}
