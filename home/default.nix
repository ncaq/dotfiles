{
  pkgs,
  lib,
  config,
  username,
  ...
}:
{
  home.username = username;

  # Nix-on-Droidなど特殊なユーザディレクトリを使う場合はそちらを優先するために、
  # デフォルト値として優先度を低めて設定します。
  home.homeDirectory = lib.mkDefault "/home/${config.home.username}";

  home.stateVersion = "25.05";

  i18n.glibcLocales = pkgs.glibcLocales.override {
    allLocales = false;
    locales = [
      "ja_JP.UTF-8/UTF-8"
      "en_US.UTF-8/UTF-8"
      "C.UTF-8/UTF-8"
    ];
  };

  programs.home-manager.enable = true;

  imports = [
    ./link.nix
    ./prompt
    ./package
  ];
}
