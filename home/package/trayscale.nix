{
  pkgs,
  lib,
  isWSL,
  ...
}:
lib.mkIf (!isWSL) {
  home.packages = [ pkgs.trayscale ];

  xdg.autostart = {
    enable = true;
    entries = [ "${pkgs.trayscale}/share/applications/dev.deedles.Trayscale.desktop" ];
  };
}
