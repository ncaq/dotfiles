{ pkgs, ... }:
{
  # サプライチェーン攻撃のリスク低減として、
  # 各JavaScriptパッケージマネージャで、
  # リリース後3日経過したバージョンをインストールするように設定します。
  # 悪意あるパッケージがpublishされてから検出・取り下げされるまでの猶予を確保する目的です。
  # 各PMで設定キー名・単位が異なる点に注意。

  # npm CLIの`min-release-age`(単位: 日)。
  # denoも`~/.npmrc`の`min-release-age`を読むため一括で効果があります。
  # home-managerには`programs.npm`がないため`home.file`で直接生成します。
  home.file.".npmrc".text = ''
    min-release-age=3
  '';

  # pnpmはhome-manager専用モジュールがないため設定ファイルを直接書きます。
  # pnpmは`~/.config/pnpm/config.yaml`を読みます(単位: 分)。
  xdg.configFile."pnpm/config.yaml".text = ''
    minimumReleaseAge: 4320
  '';

  # Yarn Berryの`npmMinimalAgeGate`(単位: 分)。
  programs = {
    yarn = {
      enable = true;
      settings.npmMinimalAgeGate = 4320;
    };

    # Bunの`minimumReleaseAge`(単位: 秒)。
    bun = {
      enable = true;
      settings.install.minimumReleaseAge = 259200;
    };
  };

  # グローバルにインストールするJavaScript関連ツール。
  home.packages = with pkgs; [
    corepack
    nodejs
    npm-check-updates
    prettier
    typescript
    typescript-language-server
    vscode-langservers-extracted
  ];
}
