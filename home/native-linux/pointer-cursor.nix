{ pkgs, ... }:
{
  # マウスカーソルを明示的に設定します。
  #
  # ツールキット非依存の唯一の共通基盤であるXcursorに対して、
  # 明示的にテーマとサイズを指定します。
  # `home.pointerCursor`は以下を一括で設定してくれるため、
  # GTKでもQtでもFirefoxでもXmonadのルートウィンドウでも同じサイズになります。
  #
  # - 環境変数`XCURSOR_THEME`と`XCURSOR_SIZE`
  # - Xリソースの`Xcursor.theme`と`Xcursor.size`
  # - `xsetroot -xcf`によるルートウィンドウのカーソル
  # - GTKの`gtk-cursor-theme-name`と`gtk-cursor-theme-size`
  # - `~/.icons`と`$XDG_DATA_HOME/icons`のテーマ配置
  home.pointerCursor = {
    enable = true;
    # Adwaitaのカーソルは24, 30, 36, 48, 72, 96のサイズを内蔵しているため、
    # 拡大してもぼやけません。
    package = pkgs.adwaita-icon-theme;
    name = "Adwaita";
    # X11には解像度に応じてマウスカーソルを自動で拡大する仕組みは存在しません。
    # あまり使わないフルHD画面などでマウスカーソルが大きすぎて困ることはそんなにないので、
    # 一番使う4Kディスプレイに合わせてサイズを36に設定します。
    size = 36;
    x11.enable = true;
    gtk.enable = true;
  };
}
