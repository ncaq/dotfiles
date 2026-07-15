{ config, ... }: {
  sops = {
    # security.acmeのDNS-01チャレンジ用環境変数ファイル。
    # lego(ACMEクライアント)がCloudflare DNS APIでTXTレコードを操作する。
    templates."cloudflare-dns-env" = {
      content = ''
        CF_DNS_API_TOKEN=${config.sops.placeholder."cloudflare-dns-api-token"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
    };
    secrets = {
      "cloudflare-dns-api-token" = {
        sopsFile = ../../secrets/cloudflare.yaml;
        key = "dns_api_token";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };
}
