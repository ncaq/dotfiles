{ pkgs, ... }:
{
  home.packages = with pkgs; [
    imagemagick
    libwebp
    mozjpeg
    oxipng
  ];
}
