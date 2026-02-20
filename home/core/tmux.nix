{ pkgs, ... }:
{
  # テキストの容量は大したことがないと考えているため、
  # 履歴は大きめに取り、
  # セッションの状態も積極的に保存する設定にしています。
  programs = {
    tmux = {
      enable = true;

      aggressiveResize = true;
      baseIndex = 1; # プログラム的には0の方が自然ですが、キーボード選択の都合がいいのは1
      clock24 = true;
      escapeTime = 0;
      focusEvents = true;
      historyLimit = 100000; # 10万行
      keyMode = "emacs";
      mouse = true;
      prefix = "C-M-z";
      terminal = "tmux-256color";
      shell = "${pkgs.zsh}/bin/zsh";

      tmuxp.enable = true;

      plugins = with pkgs.tmuxPlugins; [
        continuum
        resurrect
      ];

      extraConfig = ''
        # modus-vivendi テーマカラー
        # https://protesilaos.com/emacs/modus-themes
        # bg-main=#000000 fg-main=#ffffff bg-dim=#1e1e1e fg-dim=#989898
        # bg-mode-line-active=#505050 border=#646464 blue=#2fafff blue-warmer=#79a8ff
        # bg-active=#535353 bg-region=#5a5a5a
        set -g status-style "bg=#1e1e1e,fg=#989898"
        set -g window-status-style "bg=#1e1e1e,fg=#989898"
        set -g window-status-current-style "bg=#505050,fg=#ffffff,bold"
        set -g pane-border-style "fg=#646464"
        set -g pane-active-border-style "fg=#2fafff"
        set -g message-style "bg=#000000,fg=#ffffff"
        set -g message-command-style "bg=#000000,fg=#ffffff"
        set -g mode-style "bg=#5a5a5a,fg=#ffffff"
        set -g clock-mode-colour "#79a8ff"

        # クリップボードを連携
        set -g set-clipboard on

        # セッションをなるべく維持する
        set -g detach-on-destroy off
        set -g remain-on-exit on
        set-hook -g pane-died 'if -F "#{&&:#{==:#{session_windows},1},#{==:#{window_panes},1}}" "respawn-pane" ""'

        # プログラムが設定したタイトルを許可
        set -g set-titles on
        set -g set-titles-string "#{pane_title}"

        # ステータスバー右の時刻表記をISO 8601形式にします
        set -g status-right-length 60 # 日時で24文字でタイトルで30文字なので24+30=54なので余裕を持って60にします。
        set -g status-right " \"#{=30:pane_title}\" %Y-%m-%dT%H:%M:%S%z"
        # tmuxの秒更新のデフォルトは15秒なので、秒表示をしたいので1秒更新にします
        set -g status-interval 1

        # ウィンドウ名にはディレクトリとプロセスを表示
        set -g allow-rename on
        set -g window-status-format "#I:#{b:pane_current_path}/#{pane_current_command}"
        set -g window-status-current-format " #I:#{b:pane_current_path}/#{pane_current_command}"

        # プレフィックスなしで直接使えるキーバインド

        # ctrl+alt+o = 新規ウィンドウ(タブ)、同じディレクトリで開始
        bind -n C-M-o new-window -a -c "#{pane_current_path}"

        # ctrl+alt+q = ウィンドウを閉じる
        bind -n C-M-q kill-window

        # ウィンドウ移動
        bind -n C-M-n next-window
        bind -n C-M-t previous-window

        # ctrl+alt+s/ctrl+alt+h = ウィンドウを前(右)/後ろ(左)に配置替え
        bind -n C-M-s swap-window -t +1 \; select-window -t +1
        bind -n C-M-h swap-window -t -1 \; select-window -t -1

        # shift+up/down = 1行スクロール
        bind -n S-Up copy-mode \; send-keys -X scroll-up
        bind -n S-Down copy-mode \; send-keys -X scroll-down

        # shift+left/right = ページスクロール
        bind -n S-Left copy-mode \; send-keys -X page-up
        bind -n S-Right copy-mode \; send-keys -X page-down

        # PageUp/PageDown = ページスクロール
        bind -n PageUp copy-mode \; send-keys -X page-up
        bind -n PageDown copy-mode \; send-keys -X page-down

        # クイックウィンドウ切り替え(Alt+数字)
        bind -n M-1 select-window -t 1
        bind -n M-2 select-window -t 2
        bind -n M-3 select-window -t 3
        bind -n M-4 select-window -t 4
        bind -n M-5 select-window -t 5
        bind -n M-6 select-window -t 6
        bind -n M-7 select-window -t 7
        bind -n M-8 select-window -t 8
        bind -n M-9 select-window -t 9

        # 互いにtmuxを使っているマシンでssh接続などをした時に、
        # C-M-jでネストされた内側のtmuxを優先操作するトグル
        # offモード: 外側を均一に暗くして内側にフォーカスがあることを明示
        bind -T root C-M-j \
          set prefix None \;\
          set key-table off \;\
          set status-style "bg=#000000,fg=#535353" \;\
          set window-status-style "bg=#000000,fg=#535353" \;\
          set window-status-current-style "bg=#1e1e1e,fg=#646464" \;\
          set pane-border-style "fg=#535353" \;\
          set pane-active-border-style "fg=#535353" \;\
          if -F '#{pane_in_mode}' 'send-keys -X cancel' \;\
          refresh-client -S
        bind -T off C-M-j \
          set -u prefix \;\
          set -u key-table \;\
          set -u status-style \;\
          set -u window-status-style \;\
          set -u window-status-current-style \;\
          set -u pane-border-style \;\
          set -u pane-active-border-style \;\
          refresh-client -S

        # tmux-resurrect/continuum
        set -g @continuum-restore 'on'
        set -g @resurrect-capture-pane-contents 'on'
      '';
    };
  };
}
