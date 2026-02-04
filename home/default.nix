{
  lib,
  config,
  username,
  isWSL,
  ...
}:
{
  home.stateVersion = "25.05";

  home.username = username;
  home.homeDirectory = "/home/${config.home.username}";

  programs.home-manager.enable = true;

  imports = [
    ./link.nix
    ./prompt
    ./core
  ]
  ++ lib.optional (!isWSL) ./native-linux
  ++ lib.optional isWSL ./wsl;
}
