{
  pkgs,
  lib,
  isNativeLinux,
  dot-xmonad,
  ...
}:
lib.mkIf isNativeLinux {
  xsession = {
    enable = true;
    windowManager.command = "xmonad-launch";
  };

  home.packages = [
    dot-xmonad.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
