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
  # Cloudflare TunnelがQUICを使うときのライブラリである、
  # quic-goの推奨ガイドラインに従って、
  # UDPバッファサイズを増大させます。
  # [UDP Buffer Sizes](https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes)
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 7500000;
    "net.core.wmem_max" = 7500000;
  };
}
