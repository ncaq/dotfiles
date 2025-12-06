{
  pkgs,
  lib,
  isWSL,
  claude-desktop,
  ...
}:
lib.mkIf (!isWSL) {
  home.packages = [
    claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-with-fhs
  ];
}
