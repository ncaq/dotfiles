{
  config,
  pkgs,
  pkgs-2505,
  lib,
  ...
}:
{
  home.packages = with pkgs-2505.python3Packages; [ percol ];

  home.activation.clonePercolConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${config.home.homeDirectory}/.percol.d" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/ncaq/.percol.d.git "${config.home.homeDirectory}/.percol.d"
    fi
  '';
}
