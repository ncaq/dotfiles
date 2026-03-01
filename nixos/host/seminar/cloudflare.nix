{
  pkgs,
  config,
  ...
}:
let
  # workaround script that adds --protocol http2 flag to tunnel command.
  cloudflaredWrapper = pkgs.writeShellScriptBin "cloudflared" ''
    # Check if this is a tunnel command
    if [[ "$1" == "tunnel" ]]; then
      # Insert --protocol http2 before other tunnel arguments
      exec ${pkgs.cloudflared}/bin/cloudflared "$@" --protocol http2
    else
      # For non-tunnel commands, pass through as-is
      exec ${pkgs.cloudflared}/bin/cloudflared "$@"
    fi
  '';
  forgejoAddr = config.machineAddresses.forgejo.guest;
  mcpNixosAddr = config.machineAddresses.mcp-nixos.guest;
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
    package = cloudflaredWrapper;
    certificateFile = "/run/secrets/cloudflare-cert";
    tunnels.seminar = {
      default = "http_status:404";
      credentialsFile = "/run/secrets/cloudflare-tunnel-credentials";
      ingress = {
        "forgejo.ncaq.net" = "http://${forgejoAddr}:8080";
        "mcp-nixos.ncaq.net" = "http://${mcpNixosAddr}:8080";
      };
    };
  };
  # Cloudflare認証情報を管理。
  sops.secrets."cloudflare-cert" = {
    sopsFile = ../../../secrets/seminar/cloudflare.yaml;
    key = "cert_pem";
    owner = "root";
    group = "root";
    mode = "0400";
  };
  sops.secrets."cloudflare-tunnel-credentials" = {
    sopsFile = ../../../secrets/seminar/cloudflare.yaml;
    key = "tunnel_credentials";
    owner = "root";
    group = "root";
    mode = "0400";
  };
}
