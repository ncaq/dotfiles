{ pkgs, ... }:
{
  home.packages = with pkgs; [
    _7zz # 本家の7-Zip。コマンド名は`7zz`。
    bzip2
    gzip
    lbzip2
    patool
    pigz
    pixz
    unrar-free
    unzip
    xz
    zstd
  ];
}
