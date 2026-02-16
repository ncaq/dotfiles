{ pkgs, ... }:
{
  home.packages = with pkgs; [
    libwebp
    oxipng
  ];
}
