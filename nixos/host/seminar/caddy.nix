{ config, ... }:
let
  atticdAddr = config.machineAddresses.atticd.guest;
in
{
  services.caddy = {
    enable = true;
    email = "ncaq@ncaq.net";
    # Tailscale Serve/Funnelからのリクエストを受けるリバースプロキシ。
    # tailscaledがTLS終端を行い、ここにHTTPで転送します。
    # tailnet内からのHTTPSアクセスもtailscaledが処理するため、
    # Caddyが443をlistenする必要はありません。
    virtualHosts.":8080".extraConfig = ''
      bind 127.0.0.1
      handle_path /nix/cache/* {
        reverse_proxy http://${atticdAddr}:8080
      }
      redir /nix/cache /nix/cache/
    '';
  };
}
