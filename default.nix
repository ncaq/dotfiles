{ config, pkgs, lib, ... }: {
  # If login name is not `ncaq`, change it to your login name.
  home.username = "ncaq";
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "24.11";

  programs.home-manager.enable = true;

  imports = [ ./link.nix ];
}
