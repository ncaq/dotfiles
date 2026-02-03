{
  pkgs,
  lib,
  isNativeLinux,
  ...
}:
let
  # デフォルトだとウインドウが起動時に表示されてしまうためトレイにのみ表示するように引数を追加したdesktopファイルを作成。
  trayscale-autostart-desktop = pkgs.runCommand "trayscale-autostart.desktop" { } ''
    substitute ${pkgs.trayscale}/share/applications/dev.deedles.Trayscale.desktop $out \
      --replace-fail "Exec=trayscale" "Exec=trayscale --hide-window"
  '';
in
lib.mkIf isNativeLinux {
  home.packages = [ pkgs.trayscale ];

  xdg.autostart = {
    enable = true;
    entries = [ trayscale-autostart-desktop ];
  };
}
