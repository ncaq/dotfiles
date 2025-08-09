{
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
  ];

  home.file = {
    ".claude" = {
      source = config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/claude";
    };
  };

  # Claude Codeがシンボリックリンクされたsettings.jsonに書き込めない問題を回避
  # https://github.com/anthropics/claude-code/issues/3575
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p $HOME/.config/claude
    $DRY_RUN_CMD install -m 644 "${claudeSettingsSource}" "${config.xdg.configHome}/claude/settings.json"
  '';
}
