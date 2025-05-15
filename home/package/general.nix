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
    nkf
    opusTools
    oxipng
    parallel
    patool
    plantuml
    pstree
    rakudo
    trashy
    tree
  ];
}
