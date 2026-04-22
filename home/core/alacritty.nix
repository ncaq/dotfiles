{
  pkgs,
  lib,
  config,
  isWSL,
  osConfig,
  ...
}:
let
  alacrittyConfigFile = config.xdg.configFile."alacritty/alacritty.toml".source;
  inherit (osConfig.wsl) windowsAppData;
  windowsAlacrittyConfigFile = "${windowsAppData}/alacritty/alacritty.toml";
in
{
  programs.alacritty = {
    enable = true;
    package = pkgs.alacritty-graphics; # 画像表示対応版を選択。
    # TODO: themeにmodus-vivendiを追加して設定します。

    # UNIX環境で最優先されるパスは`$XDG_CONFIG_HOME/alacritty/alacritty.toml`であり、
    # Windows環境(WSLではなくWindowsネイティブの話)では`%APPDATA%\alacritty\alacritty.toml`です。
    settings = {
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
      # WSLのalacrittyを起動することはあまり考慮していません。
      # 話を単純にするために全ての環境でenableにしているだけなので。
      # 軽量なパッケージなのでインストールの負担にもあまりなりません。
      # Windowsのalacrittyはwingetでインストールすることを想定しています。
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

  home.activation.deployAlacrittyConfigToWindows = lib.mkIf isWSL (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ -d ${lib.escapeShellArg windowsAppData} ]; then
        $DRY_RUN_CMD mkdir -p "$(dirname ${lib.escapeShellArg windowsAlacrittyConfigFile})"
        $DRY_RUN_CMD install -m 0644 ${lib.escapeShellArg alacrittyConfigFile} ${lib.escapeShellArg windowsAlacrittyConfigFile}
      else
        $DRY_RUN_CMD echo "Windows AppData directory is not mounted: ${windowsAppData}" >&2
      fi
    ''
  );
}
