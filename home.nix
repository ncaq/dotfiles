{
  lib,
  config,
  username,
  ...
}@inputs:
{
  home.username = username;
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  imports = [ ./home/link.nix ] ++ import ./home/package { inherit builtins lib inputs; };
}
