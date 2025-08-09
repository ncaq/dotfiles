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
        if [ -f "${zshDotDir}/.zshrc" ]; then
          source "${zshDotDir}/.zshrc"
        fi
      '';
    };

    autojump.enable = true;
  };

  home.activation.cloneZshConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${zshDotDir}" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/ncaq/.zsh.d.git "${zshDotDir}"
    fi
  '';
}
