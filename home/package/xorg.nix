{ pkgs, ... }:
{
  home.packages = with pkgs.xorg; [
    xrdb
  ];

  # X リソースファイルを直接定義
  xresources.properties = {
    "Xft.dpi" = 144;
  };
}
