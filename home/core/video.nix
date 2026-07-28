{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ffmpeg
    kdePackages.kdenlive
    libaom
    svt-av1
  ];
}
