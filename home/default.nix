{
  lib,
  config,
  username,
  isWSL,
  ...
}:
{
  home.stateVersion = "25.05";

  # ユーザ名は様々な場所に影響するのでプラットフォームが名前を用意しても強制します。
  home.username = lib.mkForce username;

  # ホームディレクトリはプラットフォームの制約が強いのでプラットフォームの設定を尊重します。
  home.homeDirectory = lib.mkDefault "/home/${config.home.username}";

  programs.home-manager.enable = true;

  imports = [
    ./link.nix
    ./prompt
    ./core
  ]
  ++ lib.optional (!isWSL) ./native-linux
  ++ lib.optional isWSL ./wsl;
}
