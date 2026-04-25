{
  pkgs,
  lib,
  config,
  isWSL,
  osConfig,
  ...
}:
let
  inherit (osConfig.wsl) windowsAppData;
  # UNIX環境で最優先される設定パスの場所は`$XDG_CONFIG_HOME/alacritty/alacritty.toml`です。
  alacrittyConfigFile = config.xdg.configFile."alacritty/alacritty.toml".source;
  # Windows環境(WSLではなく)では設定パスの場所は`%APPDATA%\alacritty\alacritty.toml`です。
  windowsAlacrittyConfigFile = "${windowsAppData}/alacritty/alacritty.toml";
in
{
  programs.alacritty = {
    # WSL環境ではホストのWindowsのAlacrittyを使用したほうが良いため、
    # 本来はWSL環境では有効にする必要はありません。
    # しかし有効にしないと設定ファイルも生成されないため、
    # ややこしくなります。
    # よって全ての環境で`enable`にしています。
    # 軽量なパッケージなのでインストールの負担にはあまりなりません。
    # WindowsホストのAlacrittyはwingetでインストールすることを想定しています。
    enable = true;
    # 画像表示対応版を選択。
    package = pkgs.alacritty-graphics;
    # TODO: themeにmodus_vivendiを追加して設定します。
    # theme = "modus_vivendi";
    # themePackage = pkgs.alacritty-themes;

    settings = {
      window = {
        decorations = "None"; # タイトルバーを消す。
        startup_mode = "Maximized"; # 起動時に最大化する。
      };
      font = {
        normal = {
          family = "FirgeNerd Console";
        };
        size = 12;
      };
      # Windows環境で起動したときはWSLのシェルを起動するようにします。
      # WSLのalacrittyを起動することは考慮していません。
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
    # WSL環境ではホストのWindows環境に設定ファイルを書き込みます。
    # ブートストラップ問題は、
    # これのインストール時ぐらいは、
    # Windows Terminalとか適当なターミナルをを使えばいいので、
    # 深刻に考えていません。
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
