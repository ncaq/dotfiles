{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ffmpeg
    libaom
    svt-av1
  ];
}
