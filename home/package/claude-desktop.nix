{
  pkgs,
  lib,
  isWSL,
  claude-desktop,
  ...
}:
lib.mkIf (!isWSL) {
  home.packages = [
    claude-desktop.packages.${pkgs.system}.claude-desktop-with-fhs
  ];
}
