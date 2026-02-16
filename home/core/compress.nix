{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bzip2
    p7zip
    patool
    unrar-free
    unzip
    xz
    zlib
    zstd
  ];
}
