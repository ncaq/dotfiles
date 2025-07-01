{
  pkgs,
  lib,
  dpi,
  ...
}:
{
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
      xrdb
    ]);

  xresources.properties = lib.mkIf (dpi != null) {
    "Xft.dpi" = dpi;
  };
}
