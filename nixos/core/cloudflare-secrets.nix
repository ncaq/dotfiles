{ config, ... }: {
  # シークレットを更新するには以下のコマンドを実行します。
  # ```
  # sops secrets/cloudflare.yaml
  # ```
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
    # Cloudflare認証情報を管理。
    secrets = {
      "cloudflare-cert" = {
        sopsFile = ../../secrets/cloudflare.yaml;
        key = "cert_pem";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "cloudflare-tunnel-credentials" = {
        sopsFile = ../../secrets/cloudflare.yaml;
        key = "tunnel_credentials";
        owner = "root";
        group = "root";
        mode = "0400";
      };
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
