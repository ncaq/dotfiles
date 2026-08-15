{ inputs, ... }:
{
  # konoka側が提供するhome-managerモジュールでプラグイン一式を接続します。
  # marketplace経由ではなくビルド済みプラグインを直接読み込むことで、
  # ヘルパースクリプトまでnixで管理できます。
  imports = [ inputs.konoka.homeModules.default ];

  konoka = {
    # 全プラグインを`programs.claude-code.plugins`へ追加します。
    claude-code.enable = true;
    # 各プラグインのスキルを`programs.opencode.skills`へ展開して、
    # スキルの埋め込みコマンド用にプラグインの`bin/`を`extraPackages`へ追加します。
    opencode.enable = true;
  };
}
