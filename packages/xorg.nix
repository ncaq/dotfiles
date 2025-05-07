{ pkgs, lib, ... }:
let
  # Path to the shell script
  detectHiDpiScript = ./xorg-detect-hidpi.sh;
in
{
  # Install required packages
  home.packages = (with pkgs; [ gawk ]) ++ (with pkgs.xorg; [ xrandr ]);

  # Dynamic DPI configuration logic using activation script
  home.activation.detectAndSetDpi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${pkgs.xorg.xrandr}/bin:${pkgs.gawk}/bin:$PATH"
    # Auto-detect display resolution
    if ${lib.getExe pkgs.bash} ${detectHiDpiScript}; then
      $DRY_RUN_CMD echo "Xft.dpi: 144" > $HOME/.Xresources
    else
      # Use unlink instead of rm for safer operation
      if [ -f "$HOME/.Xresources" ]; then
        $DRY_RUN_CMD unlink "$HOME/.Xresources"
      fi
    fi
  '';
}
