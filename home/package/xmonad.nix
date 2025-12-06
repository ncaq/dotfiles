{
  pkgs,
  lib,
  isWSL,
  dot-xmonad,
  ...
}:
lib.mkIf (!isWSL) {
  xsession = {
    enable = true;
    windowManager.command = "xmonad-launch";
  };

  home.packages = [
    dot-xmonad.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
