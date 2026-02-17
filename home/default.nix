{
  lib,
  config,
  username,
  isTermux,
  isWSL,
  ...
}:
{
  home = {
    stateVersion = "25.05";

    # ユーザ名の制約が強い環境で譲ります。
    username = lib.mkDefault username;

    # ホームディレクトリはプラットフォームの制約が強いのでプラットフォームの設定を尊重します。
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
  };

  programs.home-manager.enable = true;

  imports = [
    ./link.nix
    ./prompt
    ./core
  ]
  ++ lib.optional (!(isTermux || isWSL)) ./native-linux
  ++ lib.optional isWSL ./wsl;
}
