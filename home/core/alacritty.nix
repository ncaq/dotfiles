{
  pkgs,
  lib,
  isWSL,
  nativeLinux,
  ...
}:
{
  programs.alacritty = {
    enable = nativeLinux;
    package = pkgs.alacritty-graphics; # 画像表示対応版を選択。
    # TODO: themeにmodus-vivendiを追加して設定します。

    # UNIX環境で最優先されるパスは`$XDG_CONFIG_HOME/alacritty/alacritty.toml`であり、
    # Windows環境(WSLではなくWindowsネイティブの話)では`%APPDATA%\alacritty\alacritty.toml`です。
    settings = {
      general = {
        working_directory = "~"; # 起動時のカレントディレクトリをホームディレクトリにする。
      };
      window = {
        decorations = "None"; # タイトルバーを消す。
        startup_mode = "Maximized"; # 起動時に最大化する。
      };
      font = {
        normal = {
          family = "FirgeNerd Console";
        };
      };
      # Windows環境で起動したときはWSLのシェルを起動するようにします。
      terminal = lib.mkIf isWSL {
        shell = {
          program = "wsl.exe";
          args = [
            "-d"
            "NixOS"
          ];
        };
      };
      keyboard = {
        bindings = [
          {
            key = "C";
            mods = "Control|Shift";
            action = "Copy";
          }
          {
            key = "V";
            mods = "Control|Shift";
            action = "Paste";
          }
        ];
      };
    };
  };
}
