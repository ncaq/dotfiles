{ pkgs, ... }:
{
  xresources.properties = {
    "Xft.dpi" = 144;
  };

  home.packages =
    (with pkgs; [
      arandr
      xsel
    ])
    ++ (with pkgs.xorg; [
      setxkbmap
      xkbcomp
      xmodmap
      xprop
    ]);
}
