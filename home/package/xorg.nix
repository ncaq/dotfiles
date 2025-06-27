{ pkgs, lib, ... }:
let
  xorg-detect-hidpi = pkgs.writeShellApplication {
    name = "xorg-detect-hidpi";
    runtimeInputs = with pkgs; [
      gawk
      xorg.xrandr
    ];
    text = builtins.readFile ./xorg-detect-hidpi.sh;
  };
in
{
  home.packages =
    (with pkgs; [
      arandr
      xsel
    ])
    ++ (with pkgs.xorg; [
      setxkbmap
      xkbcomp
      xmodmap
      xprop
      xrdb
    ]);

  # HiDPIモニター環境ならば`.Xresources`をそれに合わせて作成する。
  home.activation.setupXresources = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ${xorg-detect-hidpi}/bin/xorg-detect-hidpi; then
        echo "HiDPI monitor detected, creating .Xresources with 144 DPI"
        $DRY_RUN_CMD cat > $HOME/.Xresources <<EOF
    Xft.dpi: 144
    EOF
    else
      echo "Standard DPI monitor detected, removing .Xresources if exists"
      if [ -f $HOME/.Xresources ]; then
        $DRY_RUN_CMD rm -f $HOME/.Xresources
      fi
    fi
  '';
}
