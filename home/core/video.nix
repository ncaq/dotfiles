{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ffmpeg
    svt-av1
  ];
}
