{ pkgs, ... }:
{
  home.packages =
    (with pkgs; [
      arandr
      xsel
    ])
    ++ (with pkgs.xorg; [
      setxkbmap
      xinput
      xkbcomp
      xmodmap
      xprop
      xrandr
      xrdb
      xset
    ]);

  # X リソースファイルを直接定義
  xresources.properties = {
    "Xft.dpi" = 144;
  };
}
