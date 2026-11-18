# JavaScriptの開発ツールと、パッケージマネージャの設定。
#
# サプライチェーン攻撃のリスク低減として、
# 各パッケージマネージャで、
# リリース後3日経過したバージョンだけをインストールするように設定します。
# 悪意あるパッケージがpublishされてから検出・取り下げされるまでの猶予を確保する目的です。
# 設定のキー名と単位はパッケージマネージャごとに異なります。
{ pkgs, ... }:
let
  releaseAgeDays = 3;
  releaseAgeMinutes = releaseAgeDays * 24 * 60;
  releaseAgeSeconds = releaseAgeMinutes * 60;
in
{
  home = {
    # グローバルにインストールするJavaScript関連ツール。
    packages = with pkgs; [
      deno
      nodejs
      npm-check-updates
      prettier
      typescript
      yarn-berry
    ];

    # npm CLIの`min-release-age`(単位: 日)。
    # home-managerには`programs.npm`がないため`home.file`で直接生成します。
    #
    # Denoもこのファイルでカバーされます。
    # Denoは`$HOME`の`.npmrc`を読み、
    # Deno 2.8.0からは`min-release-age`にも従います。
    # [.npmrc configuration - Node and npm Compatibility](https://docs.deno.com/runtime/fundamentals/node/#.npmrc-configuration)
    # [Release v2.8.0 - denoland/deno](https://github.com/denoland/deno/releases/tag/v2.8.0)
    file.".npmrc".text = ''
      min-release-age=${toString releaseAgeDays}
    '';
  };

  # pnpmの`minimumReleaseAge`(単位: 分)。
  # home-managerには専用のモジュールがないため、
  # pnpmが読む`~/.config/pnpm/config.yaml`を直接生成します。
  xdg.configFile."pnpm/config.yaml".source = (pkgs.formats.yaml { }).generate "pnpm-config.yaml" {
    minimumReleaseAge = releaseAgeMinutes;
  };

  programs = {
    # Yarn Berryの`npmMinimalAgeGate`(単位: 分)。
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
}
