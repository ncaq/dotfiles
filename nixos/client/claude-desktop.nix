{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
{
  imports = [ inputs.claude-desktop.nixosModules.default ];

  programs.claude-desktop.enable = true;

  # PCが起動しているときは基本的にモバイルのClaudeアプリなどからClaude Desktopに繋げるように、
  # GUIセッションの開始時にトレイへ常駐させます。
  # アプリの設定にある自動起動は`~/.config/autostart/claude-desktop.desktop`を作りますが、
  # Execがラッパを通らない実行ファイルを指すのでNixOSでは使わずにこちらで宣言します。
  # ファイル名を揃えているので、
  # 誤ってアプリ側で有効にしてもユーザ側のファイルが優先され二重には起動しません。
  environment.systemPackages = [
    (pkgs.makeDesktopItem {
      name = "claude-desktop";
      destination = "/etc/xdg/autostart";
      desktopName = "Claude";
      # `--startup`はアプリ自身がログイン時の起動に使う引数で、
      # メインウィンドウを開かずにトレイだけを出します。
      exec = "${lib.getExe config.programs.claude-desktop.package} --startup";
      icon = "claude-desktop";
    })
  ];
}
