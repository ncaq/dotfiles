{ config, ... }:
{
  imports = [ ../../lib/git-repo-subscribe.nix ];

  programs.git-repo-subscribe.repositories = {
    dot-emacs = {
      url = "https://github.com/ncaq/.emacs.d.git";
      path = "${config.home.homeDirectory}/.emacs.d";
    };
    dot-zsh = {
      url = "https://github.com/ncaq/.zsh.d.git";
      path = "${config.programs.zsh.dotDir}/.zsh.d";
    };
    home-manager = {
      url = "https://github.com/nix-community/home-manager.git";
      path = "${config.home.homeDirectory}/Desktop/home-manager";
    };
    infra-ncaq-net = {
      url = "https://github.com/ncaq/infra.ncaq.net.git";
      path = "${config.home.homeDirectory}/Desktop/infra.ncaq.net";
    };
    nixpkgs = {
      url = "https://github.com/NixOS/nixpkgs.git";
      path = "${config.home.homeDirectory}/Desktop/nixpkgs";
    };
  };
}
