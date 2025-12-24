{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  ...
}:
let
  claudeSettingsSource = ../config/claude/settings.json;
in
{
  home.packages = [
    pkgs-unstable.claude-code
    # Claude Codeのsandbox機能を利用する時に必要。
    pkgs.bubblewrap
    pkgs.socat
  ];

  home.file = {
    # Claude Codeがxdgに従ったり従わなかったり不安定なためシンボリックリンクを配置します。
    ".claude" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/claude";
    };
    # Claude Codeに必要なユーザプロンプトを配置します。
    "${config.xdg.configHome}/claude/CLAUDE.md".text = config.prompt.coding-agent;
  };

  # Claude Codeがシンボリックリンクされたsettings.jsonに書き込めない問題を回避するために、
  # シンボリックリンクを配置するのではなくインストール時に毎回コピーします。
  # https://github.com/anthropics/claude-code/issues/3575
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.config/claude
    $DRY_RUN_CMD install -m 644 "${claudeSettingsSource}" "${config.xdg.configHome}/claude/settings.json"
  '';
}
