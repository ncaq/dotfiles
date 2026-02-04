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
    virtualHosts."cache.nix.ncaq.net".extraConfig = ''
      tls {
        dns cloudflare {file.${config.sops.secrets."cloudflare-dns-api-token".path}}
      }
      reverse_proxy http://${atticdAddr}:8080
    '';
    # tailscale serveはlocalhost宛のプロキシのみサポートするため、
    # caddyで中継します。
    # httpsが解決されたものをhttp同士で中継する必要があるため、
    # わかりやすさも考えてプロトコルを明示的に指定しています。
    # Tailscale Funnelは /nix/cache/ パスで公開するため、
    # そのパスを処理してatticに転送します。
    virtualHosts."http://localhost:8081".extraConfig = ''
      handle /nix/cache/* {
        uri strip_prefix /nix/cache
        reverse_proxy http://${atticdAddr}:8080
      }
    '';
  };
}
