{ pkgs, ... }:
{
  home.packages = with pkgs; [
    imagemagick
    libavif
    libwebp
    mozjpeg
    oxipng
  ];
}
