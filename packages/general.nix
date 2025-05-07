{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bash
    cachix
    docker
    docker-compose
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
