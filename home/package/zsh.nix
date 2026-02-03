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
        if [[ -x "$(command -v ${lib.getExe pkgs.tmux})" ]] && [[ -z "$TMUX" ]] && [[ $- == *i* ]]; then
          if ! ${lib.getExe pkgs.tmux} new -A -s master; then
            echo "Warning: tmux failed to start. Falling back to normal shell." >&2
          else
            # tmuxセッションが正常終了した場合、zshシェルも終了します。
            exit $?
          fi
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
