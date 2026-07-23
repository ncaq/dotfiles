{
  pkgs-unstable,
  config,
  konoka,
  ...
}:
{
  programs.opencode = {
    enable = true;
    # コーディングエージェントは更新が早くサーバも最新バージョンを要求しがちなのでunstableを使います。
    package = pkgs-unstable.opencode;
    # グローバル指示です。
    # `~/.config/opencode/AGENTS.md`に配置されます。
    context = config.prompt.codingAgent;
    # `mcp.nix`と連携します。
    enableMcpIntegration = true;
    # konokaのスキルをflake input経由で読み込みます。
    # `~/.config/opencode/skills/<skill>/`にそれぞれsymlinkされます。
    inherit (konoka) skills;
    # OpenCodeプロセスのPATHにkonokaプラグインの`bin/`を追加します。
    # スキルの埋め込みコマンド(`commit-prepare`など)を呼び出せるようにします。
    # `home.packages`と違いユーザ全体のPATHは汚さず、
    # `opencode`実行時のみに限定できます。
    # `bin/`を持たないプラグインが混ざっても`makeBinPath`が単に空を返すだけで害はないため、
    # 対象を絞らず全プラグインをまとめて渡します。
    extraPackages = map (n: konoka.plugins.${n}) konoka.allPluginNames;
    # `~/.config/opencode/opencode.json`に配置されます。
    settings = {
      # パッケージはNixで管理しているため自己アップデートは無効にします。
      autoupdate = false;
      # デフォルトモデルは現在あえて宣言しません。
    };
  };
}
