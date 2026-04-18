{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.custom.trayscale;
  # デフォルトだとウインドウが起動時に表示されてしまうためトレイにのみ表示するように引数を追加したdesktopファイルを作成。
  trayscale-autostart-desktop = pkgs.runCommand "trayscale-autostart.desktop" { } ''
    substitute ${pkgs.trayscale}/share/applications/dev.deedles.Trayscale.desktop $out \
      --replace-fail "Exec=trayscale" "Exec=trayscale --hide-window"
  '';
in
{
  options.custom.trayscale.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to enable trayscale.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.trayscale ];
    xdg.autostart = {
      enable = true;
      entries = [ trayscale-autostart-desktop ];
    };
  };
}
