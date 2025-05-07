{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bash
    cachix
    fd
    file
    findutils
    gnugrep
    go
    htop
    jq
    less
    nano
    nix-prefetch
    plantuml
    plocate
    python3
    ripgrep
    rsync
    tree
    wget
    zsh
  ];
}
