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
    enable = true;
    client.enable = true;
    defaultEditor = true;
  };

  home.activation.cloneEmacsConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${config.home.homeDirectory}/.emacs.d" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone \
        https://github.com/ncaq/.emacs.d.git \
        "${config.home.homeDirectory}/.emacs.d"
    fi
  '';
}
