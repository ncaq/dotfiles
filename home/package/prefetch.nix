{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nix-prefetch
    nix-prefetch-bzr
    nix-prefetch-cvs
    nix-prefetch-docker
    nix-prefetch-git
    nix-prefetch-github
    nix-prefetch-hg
    nix-prefetch-svn
    nurl
    prefetch-npm-deps
    prefetch-yarn-deps
  ];
}
