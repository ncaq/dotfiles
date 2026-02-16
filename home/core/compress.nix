{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bzip2
    gzip
    p7zip
    patool
    unrar-free
    unzip
    xz
    zstd
  ];
}
