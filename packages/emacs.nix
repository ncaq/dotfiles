{
  config,
  pkgs,
  lib,
  ...
}:
{
  programs.emacs = {
    enable = true;
  };

  services.emacs = {
    client.enable = true;
    defaultEditor = true;
  };

  home.sessionVariables =
    let
      editor = "emacsclient -a emacs";
    in
    {
      EDITOR = editor;
      VISUAL = editor;
    };

  # `git clone .emacs.d`
  home.activation.cloneEmacsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${config.home.homeDirectory}/.emacs.d" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/ncaq/.emacs.d.git "${config.home.homeDirectory}/.emacs.d"
    else
      echo "Info: ${config.home.homeDirectory}/.emacs.d already exists, skipping clone"
    fi
  '';
}
