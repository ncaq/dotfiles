{
  config,
  lib,
  username,
  ...
}:
{
  home.username = username;
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  imports = [ ./link.nix ] ++ import ./package { inherit builtins lib; };
}
