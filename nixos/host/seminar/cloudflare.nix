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
  forgejoAddr = config.containerAddresses.forgejo.container;
  atticdAddr = config.containerAddresses.atticd.container;
in
{
  # Cloudflare認証情報を管理。
  sops.secrets."cloudflare-cert" = {
    sopsFile = ../../../secrets/seminar/cloudflare.yaml;
    key = "cert_pem";
    mode = "0444";
  };
  sops.secrets."cloudflare-tunnel-credentials" = {
    sopsFile = ../../../secrets/seminar/cloudflare.yaml;
    key = "tunnel_credentials";
    mode = "0444";
  };

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
        "forgejo-ssh.ncaq.net" = "ssh://${forgejoAddr}:2222";
        "forgejo.ncaq.net" = "http://${forgejoAddr}:8080";
        "nix-cache.ncaq.net" = "http://${atticdAddr}:8080";
      };
    };
  };
}
