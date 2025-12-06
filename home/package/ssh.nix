{ pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "forgejo-ssh.ncaq.net" = {
        proxyCommand = ''
          ${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h
        '';
      };
    };
  };
}
