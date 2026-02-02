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

  # home-manager環境だとnixosの設定が効いてないので有効になっていないことがあるので、
  # 明示的に再度指定。
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  imports = [
    ./link.nix
    ./prompt
    ./package
  ];
}
