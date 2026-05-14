{ pkgs, ... }:
let
  releaseAgeDays = 3;
  releaseAgeMinutes = releaseAgeDays * 24 * 60;
  releaseAgeSeconds = releaseAgeMinutes * 60;
in
{
  # サプライチェーン攻撃のリスク低減として、
  # 各JavaScriptパッケージマネージャで、
  # リリース後3日経過したバージョンをインストールするように設定します。
  # 悪意あるパッケージがpublishされてから検出・取り下げされるまでの猶予を確保する目的です。
  # 各PMで設定キー名・単位が異なる点に注意。

  # Denoはユーザグローバルの設定ファイルを公式にはサポートしていないので未対応です。

  # npm CLIの`min-release-age`(単位: 日)。
  # home-managerには`programs.npm`がないため`home.file`で直接生成します。
  home.file.".npmrc".text = ''
    min-release-age=${toString releaseAgeDays}
  '';

  # pnpmはhome-manager専用モジュールがないため設定ファイルを直接書きます。
  # pnpmは`~/.config/pnpm/config.yaml`を読みます(単位: 分)。
  xdg.configFile."pnpm/config.yaml".source = (pkgs.formats.yaml { }).generate "pnpm-config.yaml" {
    minimumReleaseAge = releaseAgeMinutes;
  };

  # Yarn Berryの`npmMinimalAgeGate`(単位: 分)。
  programs = {
    yarn = {
      enable = true;
      settings.npmMinimalAgeGate = releaseAgeMinutes;
    };

    # Bunの`minimumReleaseAge`(単位: 秒)。
    bun = {
      enable = true;
      settings.install.minimumReleaseAge = releaseAgeSeconds;
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
