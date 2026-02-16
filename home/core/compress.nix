{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bzip2
    gzip
    lbzip2
    p7zip
    patool
    pigz
    pixz
    unrar-free
    unzip
    xz
    zstd
  ];
}
