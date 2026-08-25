{ config, ... }:
let
  # DNS-01チャレンジで取得するLet's Encrypt証明書の共通設定。
  dns01Cert = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.templates."cloudflare-dns-env".path;
    group = "caddy";
  };
in
{
  security.acme.certs = {
    # garage.ncaq.netのLet's Encrypt証明書をDNS-01チャレンジで取得。
    # Cloudflare Tunnelの接続先は変更せず(Garage直接のまま)、
    # niks3-publicコンテナからの内部アクセスのみCaddy HTTPS経由にする。
    "garage.ncaq.net" = dns01Cert;
    # niks3-public.ncaq.netも同様に、
    # ホスト内部からのアクセスをCaddy HTTPS経由でバイパスするために取得する。
    # caddy.nix参照。
    "niks3-public.ncaq.net" = dns01Cert;
  };
}
