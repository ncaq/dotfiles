{
  config,
  ...
}:
let
  forgejoAddr = config.machineAddresses.forgejo.guest;
  mcpNixosAddr = config.machineAddresses.mcp-nixos.guest;
  garageAddr = config.machineAddresses.garage.guest;
  niks3PublicAddr = config.machineAddresses.niks3-public.guest;
in
{
  # Managed by sops-nix. To update the secrets:
  # ```
  # sops secrets/seminar/cloudflare.yaml
  # ```
  # To initialize (first time only):
  # ```
  # nix run 'nixpkgs#cloudflared' -- tunnel login
  # ```
  # Then copy cert.pem content to cert_pem key and
  # tunnel credentials JSON to tunnel_credentials key in the sops file.
  services.cloudflared = {
    enable = true;
    certificateFile = config.sops.secrets."cloudflare-cert".path;
    tunnels.seminar = {
      default = "http_status:404";
      credentialsFile = config.sops.secrets."cloudflare-tunnel-credentials".path;
      ingress = {
        "forgejo.ncaq.net" = "http://${forgejoAddr}:8080";
        "mcp-nixos.ncaq.net" = "http://${mcpNixosAddr}:8080";
        "garage.ncaq.net" = "http://${garageAddr}:3900";
        "niks3-public.ncaq.net" = "http://${niks3PublicAddr}:5751";
      };
    };
  };
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
        sopsFile = ../../../secrets/seminar/cloudflare.yaml;
        key = "cert_pem";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "cloudflare-tunnel-credentials" = {
        sopsFile = ../../../secrets/seminar/cloudflare.yaml;
        key = "tunnel_credentials";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      "cloudflare-dns-api-token" = {
        sopsFile = ../../../secrets/seminar/cloudflare.yaml;
        key = "dns_api_token";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };
}
