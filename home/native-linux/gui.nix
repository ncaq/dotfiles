# 他のプラットフォームに移植版や似たようなソフトウェアが存在するなど、
# ネイティブLinuxで使わないとあまり意味がないソフトウェアをリストアップします。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    discord
    eog
    evince
    gimp
    inkscape
    libreoffice
    nautilus
    rhythmbox
    slack
    virtualbox
    vlc
    youtube-music
    zoom-us
  ];
}
