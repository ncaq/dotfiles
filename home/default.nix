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

    # NixOSを使っていない環境向けにも日本語ロケールを指定します。
    language.base = "ja_JP.UTF-8";

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
