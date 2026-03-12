{ config, ... }:
let
  atticdAddr = config.machineAddresses.atticd.guest;
  garageAddr = config.machineAddresses.garage.guest;
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
    # niks3-publicコンテナからGarageへのCloudflare Tunnelバイパス用TLS termination proxy。
    # Cloudflare Tunnel経由だとContent-Encoding: zstdが透過的に解凍され、
    # niks3のreadProxyがS3上のzstd圧縮narinfoを正しく読めなくなる。
    # コンテナ内のhostsでgarage.ncaq.netをhostAddressに向け、
    # Caddy(Let's Encrypt証明書)経由でGarageに直接HTTP接続することでバイパスする。
    # presigned URLはhttps://garage.ncaq.net/...のまま維持され、
    # 外部クライアント(GitHub Actions)はCloudflare Tunnel経由でアクセスする。
    virtualHosts."garage.ncaq.net" = {
      useACMEHost = "garage.ncaq.net";
      extraConfig = ''
        reverse_proxy http://${garageAddr}:3900
      '';
    };
  };
  # コンテナのvethインターフェースからCaddyの443への接続を許可する。
  networking.firewall.interfaces."ve-+".allowedTCPPorts = [ 443 ];
  # garage.ncaq.netのLet's Encrypt証明書をDNS-01チャレンジで取得。
  # Cloudflare Tunnelの接続先は変更せず(Garage直接のまま)、
  # niks3-publicコンテナからの内部アクセスのみCaddy HTTPS経由にする。
  security.acme = {
    acceptTerms = true;
    defaults.email = "ncaq@ncaq.net";
    certs."garage.ncaq.net" = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."cloudflare-dns-env".path;
      group = "caddy";
    };
  };
}
