# 他のプラットフォームに移植版や似たようなソフトウェアが存在するなど、
# ネイティブLinuxで使わないとあまり意味がないソフトウェアをリストアップします。
{
  pkgs,
  lib,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      eog
      evince
      gimp
      inkscape
      libreoffice
      nautilus
      rhythmbox
      vlc
      youtube-music
    ]
    ++ lib.optionals stdenv.hostPlatform.isx86_64 [
      discord
      slack
      virtualbox
      zoom-us
    ];
}
