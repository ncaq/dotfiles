# Windows版などがあったりして、ネイティブLinux以外で使うメリットの薄いGUIアプリケーション。
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    discord
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
