# [home-manager](https://github.com/nix-community/home-manager)が使う設定ファイルを管理します。
{
  lib,
  config,
  username,
  isTermux,
  isWSL,
  isServer,
  ...
}:
let
  nativeLinux = !(isTermux || isWSL);
  # 人が直接操作するGUIのある環境。
  client = nativeLinux && !isServer;
in
{
  home = {
    stateVersion = "26.05";

    # NixOSを使っていない環境向けにも日本語ロケールを指定します。
    language.base = "ja_JP.UTF-8";

    # ユーザ名の制約が強い環境で譲ります。
    username = lib.mkDefault username;

    # ホームディレクトリはプラットフォームの制約が強いのでプラットフォームの設定を尊重します。
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
  };

  programs.home-manager.enable = true;

  # ネイティブのLinuxと言うのはホストシステムを意識しなくても単体で使える環境という程度の意味です。
  _module.args.nativeLinux = nativeLinux;

  imports = [
    ../prompt
    ./core
    ./link.nix
  ]
  ++ lib.optional nativeLinux ./native-linux
  ++ lib.optional client ./client
  ++ lib.optional isWSL ./wsl;
}
