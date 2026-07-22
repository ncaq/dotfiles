{ pkgs-unstable, config, ... }:
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
    # `~/.config/opencode/opencode.json`に配置されます。
    settings = {
      # パッケージはNixで管理しているため自己アップデートは無効にします。
      autoupdate = false;
      # デフォルトモデルは現在あえて宣言しません。
    };
  };
}
