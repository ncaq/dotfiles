{ config, ... }:
let
  atticdAddr = config.machineAddresses.atticd.guest;
  garageAddr = config.machineAddresses.garage.guest;
  niks3PublicHostAddr = config.machineAddresses.niks3-public.host;
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
    # Tailscale Funnelがホストの443を使うため、
    # niks3-publicコンテナのhostAddress側vethのみにバインドする。
    # vethはコンテナ起動時に作成されるため、
    # Caddy起動時に存在しない場合があり、
    # boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind"が必要。
    virtualHosts."garage.ncaq.net" = {
      useACMEHost = "garage.ncaq.net";
      extraConfig = ''
        bind ${niks3PublicHostAddr}
        reverse_proxy http://${garageAddr}:3900
      '';
    };
  };
  # コンテナのvethインターフェースからCaddyの443への接続を許可する。
  networking.firewall.interfaces."ve-+".allowedTCPPorts = [ 443 ];
  # vethインターフェースはコンテナ起動時に作成されるため、
  # Caddy起動時にはまだバインド先IPが存在しない場合がある。
  # ip_nonlocal_bindを有効にして未割当アドレスへのバインドを許可する。
  boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;
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
