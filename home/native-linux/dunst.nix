{ pkgs, ... }:
{
  # `org.freedesktop.Notifications`を提供する通知デーモン。
  # 無いとnm-appletなどの通知が`ServiceUnknown`で失敗して何も表示されません。
  services.dunst = {
    enable = true;
    settings = {
      global = {
        # XMonadではマウスを動かさずキーボードでフォーカスだけ移すことが多いので、
        # 入力フォーカスのあるウィンドウのモニタに表示します。
        # フォーカスが無い時はdunstがマウスの位置に切り替えます。
        follow = "keyboard";
        # 上端のxmobarとtrayerに被らないように下へずらします。
        # `offset`にも`Xft.dpi`由来の倍率が掛かるので論理ピクセルで書きます。
        origin = "top-right";
        offset = "(16, 24)";
        width = "(300, 500)";
        height = "(0, 300)";
        notification_limit = 8;

        # fontconfigの既定のサンセリフに任せて日本語もフォールバックさせます。
        font = "sans-serif 12";
        # Adwaitaは`-symbolic`のアイコンしか持たず、
        # 通知でよく使われる`dialog-warning`や`nm-device-wired`などが見つからないので、
        # 汎用のアイコンが揃っているPapirusを優先します。
        # アプリ自身のアイコンはhicolorから探します。
        enable_recursive_icon_lookup = true;
        icon_theme = "Papirus-Dark, hicolor";
        max_icon_size = 48;

        frame_width = 2;
        corner_radius = 6;
        separator_color = "frame";
        padding = 10;
        horizontal_padding = 12;
        gap_size = 4;

        # 離席中に届いた通知を見逃さないように、
        # 一定時間操作が無い間はタイムアウトさせません。
        idle_threshold = 120;
        history_length = 100;

        mouse_left_click = "do_action, close_current";
        mouse_middle_click = "close_current";
        mouse_right_click = "close_all";

        # 既定の`/usr/bin/xdg-open`はNixOSに存在しません。
        browser = "${pkgs.xdg-utils}/bin/xdg-open";
      };

      urgency_low = {
        background = "#222222";
        foreground = "#aaaaaa";
        frame_color = "#555555";
        highlight = "#555555";
        timeout = 5;
      };

      urgency_normal = {
        background = "#222222";
        foreground = "#dddddd";
        frame_color = "#4a90d9";
        highlight = "#4a90d9";
        timeout = 10;
      };

      urgency_critical = {
        background = "#2b1b1b";
        foreground = "#eeeeee";
        frame_color = "#d9534f";
        highlight = "#d9534f";
        timeout = 0;
      };
    };
  };
  # dunstはアイコンテーマを`XDG_DATA_DIRS`から探すのでプロファイルに入れます。
  home.packages = [ pkgs.papirus-icon-theme ];
}
