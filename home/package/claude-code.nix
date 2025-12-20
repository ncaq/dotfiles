{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  www-ncaq-net,
  ...
}:
let
  claudeSettingsSource = ../config/claude/settings.json;
in
{
  home.packages = [
    pkgs-unstable.claude-code
    # Claude Codeのsandbox機能を利用するために必要。
    pkgs.bubblewrap
    pkgs.socat
  ];

  home.file = {
    # Claude Codeがxdgに従ったり従わなかったり不安定なためシンボリックリンクを配置します。
    ".claude" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/claude";
    };
    # Claude Codeに必要なユーザプロンプト全体を連結して配置します。
    "${config.xdg.configHome}/claude/CLAUDE.md".text = lib.concatStringsSep "\n" [
      (builtins.readFile ../../prompt/for-llm.md)
      (builtins.readFile ../../prompt/environment/os.md)
      (builtins.readFile ../../prompt/environment/hardware.md)
      (builtins.readFile ../../prompt/profile.md)
      (builtins.readFile "${www-ncaq-net}/site/about.md")
      (builtins.readFile ../../prompt/command.md)
      (builtins.readFile ../../prompt/naming-rule.md)
      (builtins.readFile ../../prompt/use-error-info.md)
      (builtins.readFile ../../prompt/check-work.md)
      (builtins.readFile ../../prompt/test.md)
    ];
  };

  # Claude Codeがシンボリックリンクされたsettings.jsonに書き込めない問題を回避
  # https://github.com/anthropics/claude-code/issues/3575
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.config/claude
    $DRY_RUN_CMD install -m 644 "${claudeSettingsSource}" "${config.xdg.configHome}/claude/settings.json"
  '';
}
