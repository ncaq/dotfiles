{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cachix
    dmd
    fd
    ffmpeg
    file
    htop
    jq
    libwebp
    lsof
    nkf
    opusTools
    oxipng
    parallel
    patool
    plantuml
    pstree
    rakudo
    shellcheck
    squashfsTools
    trashy
    tree
  ];
}
