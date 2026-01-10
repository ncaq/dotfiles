{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nix-prefetch
    nix-prefetch-git
    nix-prefetch-github
  ];
}
