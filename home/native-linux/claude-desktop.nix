{
  pkgs,
  claude-desktop,
  ...
}:
{
  home.packages = [
    claude-desktop.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop-with-fhs
  ];
}
