{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ffmpeg
    libwebp
    opusTools
    oxipng
    p7zip
    patool
  ];
}
