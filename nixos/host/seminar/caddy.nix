{
  pkgs,
  config,
  ...
}:
let
  atticdAddr = config.containerAddresses.atticd.container;
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
    virtualHosts."seminar.border-saurolophus.ts.net".extraConfig = ''
      respond "Hello from seminar!"
    '';
    virtualHosts."cache.nix.ncaq.net".extraConfig = ''
      tls {
        dns cloudflare {file.${config.sops.secrets."cloudflare-dns-api-token".path}}
      }
      reverse_proxy http://${atticdAddr}:8080
    '';
  };
}
