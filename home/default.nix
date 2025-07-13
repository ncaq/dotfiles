{
  config,
  username,
  ...
}:
{
  home.username = username;
  home.homeDirectory = "/home/${config.home.username}";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  imports = [
    ./link.nix
    ./package
  ];
}
