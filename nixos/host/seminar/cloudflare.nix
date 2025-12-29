{
  pkgs,
  config,
  username,
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
  # To initialize, run in server:
  # ```
  # nix run 'nixpkgs#cloudflared' -- tunnel login
  # ```
  # copy credentialsFile from terraform client to server.
  services.cloudflared = {
    enable = true;
    package = cloudflaredWrapper;
    certificateFile = "/home/${username}/.cloudflared/cert.pem";
    tunnels.seminar = {
      default = "http_status:404";
      credentialsFile = "/home/${username}/.cloudflared/tunnel-seminar.json";
      ingress = {
        "forgejo.ncaq.net" = "http://${forgejoAddr}";
        "forgejo-ssh.ncaq.net" = "ssh://${forgejoAddr}:22";
        "nix-cache.ncaq.net" = "http://${atticdAddr}";
      };
    };
  };
}
