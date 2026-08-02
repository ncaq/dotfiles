{ config, ... }: {
  # garage.ncaq.netのLet's Encrypt証明書をDNS-01チャレンジで取得。
  # Cloudflare Tunnelの接続先は変更せず(Garage直接のまま)、
  # niks3-publicコンテナからの内部アクセスのみCaddy HTTPS経由にする。
  security.acme.certs."garage.ncaq.net" = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.templates."cloudflare-dns-env".path;
    group = "caddy";
  };
}
