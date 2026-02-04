{ pkgs, ... }:
let
  # デフォルトだとウインドウが起動時に表示されてしまうためトレイにのみ表示するように引数を追加したdesktopファイルを作成。
  trayscale-autostart-desktop = pkgs.runCommand "trayscale-autostart.desktop" { } ''
    substitute ${pkgs.trayscale}/share/applications/dev.deedles.Trayscale.desktop $out \
      --replace-fail "Exec=trayscale" "Exec=trayscale --hide-window"
  '';
in
{
  home.packages = [ pkgs.trayscale ];

  xdg.autostart = {
    enable = true;
    entries = [ trayscale-autostart-desktop ];
  };
}
