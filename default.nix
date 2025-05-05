{ config, pkgs, lib, ... }: {
  # If login name is not `ncaq`, change it to your login name.
  home.username = "ncaq";
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  imports = [ ./link.nix ] ++ import ./programs { inherit builtins lib; };

  home.packages = with pkgs; [
    arandr
    bash
    bat
    bat-extras.batdiff
    bat-extras.batgrep
    bat-extras.batman
    bat-extras.batpipe
    bat-extras.batwatch
    bat-extras.prettybat
    chromium
    copyq
    direnv
    docker
    docker-compose
    emacs
    fd
    file
    findutils
    firefox
    gimp
    git
    git-lfs
    gnugrep
    go
    htop
    inkscape
    jq
    kitty
    less
    libreoffice
    lightdm
    nano
    obs-studio
    pavucontrol
    plocate
    python3
    rhythmbox
    ripgrep
    rsync
    starship
    thunderbird
    trayer
    tree
    vlc
    wget
    xkeysnail
    xorg.xrandr
    xorg.xset
    xsel
    zsh
  ];
}
