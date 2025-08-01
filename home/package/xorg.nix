{ pkgs, ... }:
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
      xrandr
      xrdb
    ]);
}
