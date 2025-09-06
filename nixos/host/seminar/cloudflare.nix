{ username, ... }:
{
  # To initialize, run in server:
  # ```
  # nix run 'nixpkgs#cloudflared' -- tunnel login
  # ```
  # copy credentialsFile from terraform client to server.
  services.cloudflared = {
    enable = true;
    certificateFile = "/home/${username}/.cloudflared/cert.pem";
    tunnels.seminar = {
      default = "http_status:404";
      credentialsFile = "/home/${username}/.cloudflared/tunnel-seminar.json";
      ingress = {
        "nix-cache.ncaq.net" = "http://localhost:10000";
      };
    };
  };
}
