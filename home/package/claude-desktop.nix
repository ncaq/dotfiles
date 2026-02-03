{
  pkgs,
  lib,
  isNativeLinux,
  claude-desktop,
  ...
}:
lib.mkIf isNativeLinux {
  home.packages = [
    claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-with-fhs
  ];
}
