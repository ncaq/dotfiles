{ pkgs, ... }:
{
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "forgejo-ssh.ncaq.net" = {
        proxyCommand = ''
          ${pkgs.cloudflared}/bin/cloudflared access ssh --hostname %h
        '';
      };
    };
  };
}
