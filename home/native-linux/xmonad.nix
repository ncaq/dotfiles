{
  pkgs,
  lib,
  inputs,
  ...
}:
lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
  xsession = {
    enable = true;
    windowManager.command = "xmonad-launch";
  };

  home.packages = [
    inputs.dot-xmonad.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
