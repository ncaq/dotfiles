{
  lib,
  config,
  username,
  isWSL,
  ...
}:
{
  home.username = username;
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  imports = [
    ./link.nix
    ./prompt
    ./core
  ]
  ++ lib.optional (!isWSL) ./native-linux
  ++ lib.optional isWSL ./wsl;
}
