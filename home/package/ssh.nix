{ pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "seminar-ssh.ncaq.net" = {
        proxyCommand = ''
          ${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h
        '';
      };
      "forgejo-ssh.ncaq.net" = {
        proxyCommand = ''
          ${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h
        '';
        extraOptions = {
          # Forgejo's built-in SSH server doesn't support post-quantum key exchange.
          WarnWeakCrypto = "no-pq-kex";
        };
      };
    };
  };
}
