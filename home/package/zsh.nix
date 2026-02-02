{
  pkgs,
  config,
  lib,
  ...
}:
let
  zshDotDir = "${config.home.homeDirectory}/.zsh.d";
in
{
  programs = {
    zsh = {
      enable = true;

      # Nixの自動生成するものではないユーザのzshrcを読み込む。
      initContent = ''
        if [ -x "$(command -v ${lib.getExe pkgs.tmux})" ] && [[ -z "$TMUX" ]] && [[ $- == *i* ]]; then
          exec ${lib.getExe pkgs.tmux} new -A -s master
        fi
        if [ -f "${zshDotDir}/.zshrc" ]; then
          source "${zshDotDir}/.zshrc"
        fi
      '';
    };

    autojump.enable = true;
  };

  home.shell.enableZshIntegration = true;

  home.activation.cloneZshConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${zshDotDir}" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/ncaq/.zsh.d.git "${zshDotDir}"
    fi
  '';
}
