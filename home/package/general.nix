{ pkgs, ... }:
{
  home.packages = with pkgs; [
    cachix
    dmd
    fd
    ffmpeg
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
  ];
}
