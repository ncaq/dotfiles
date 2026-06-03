{
  pkgs,
  config,
  lib,
  ...
}:
let
  zshDotDir = config.programs.zsh.dotDir;
  zshUserDotDir = "${zshDotDir}/.zsh.d";
in
{
  programs = {
    zsh = {
      enable = true;

      # Nixの自動生成するものではないユーザのzshrcを読み込む。
      initContent = ''
        if [[ -x "$(command -v ${lib.getExe pkgs.tmux})" ]] \
          && [[ -z "$TMUX" ]] && [[ $- == *i* ]]; then
          # tmuxがインストールされていて、
          # 現在tmuxセッション内でなく、
          # かつ対話型シェルの場合にtmuxセッションを開始します。
          if ${lib.getExe pkgs.tmux} new -A -s master; then
            # tmuxセッションが正常終了した場合、zshシェルも終了します。
            exit
          else
            # tmuxが異常終了した場合、通常のシェルにフォールバックします。
            echo "Warning: tmux failed to start. Falling back to normal shell." >&2
          fi
        fi
        # tmuxセッションの中に既にいる場合はユーザの設定を読み込みます。
        if [ -f "${zshUserDotDir}/.zshrc" ]; then
          source "${zshUserDotDir}/.zshrc"
        fi
      '';
    };

    autojump.enable = true;
  };

  home = {
    shell.enableZshIntegration = true;

    activation.cloneZshConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${zshUserDotDir}" ]; then
        $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/ncaq/.zsh.d.git "${zshUserDotDir}"
      fi
    '';
  };
}
