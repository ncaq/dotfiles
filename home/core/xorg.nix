{ pkgs, ... }:
{
  home.packages = with pkgs; [
    arandr
    setxkbmap
    xkbcomp
    xmodmap
    xprop
    xrandr
    xrdb
    xsel
  ];
}
