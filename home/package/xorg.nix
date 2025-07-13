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

  services.autorandr.enable = true;
  programs.autorandr.enable = true;
}
