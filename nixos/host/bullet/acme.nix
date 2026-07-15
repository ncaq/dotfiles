{ config, ... }: {
  # `comfy-ui.localhost.ncaq.net`用のLet's Encrypt証明書をDNS-01チャレンジで取得。
  # AレコードはCloudflare側で`127.0.0.1`を返すためHTTP-01は使えない。
  security.acme.certs."comfy-ui.localhost.ncaq.net" = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.templates."cloudflare-dns-env".path;
    group = "caddy";
  };
}
