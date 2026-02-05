{
  pkgs,
  lib,
  dot-xmonad,
  ...
}:
lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
  xsession = {
    enable = true;
    windowManager.command = "xmonad-launch";
  };

  home.packages = [
    dot-xmonad.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
