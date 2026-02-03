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
        set -g detach-on-destroy off
        set -g remain-on-exit on
        set-hook -g pane-died 'if -F "#{&&:#{==:#{session_windows},1},#{==:#{window_panes},1}}" "respawn-pane" ""'

        # プログラムが設定したタイトルを許可しつつ、
        # ウィンドウ名にはディレクトリとプロセスを表示
        set -g allow-rename on
        set -g set-titles on
        set -g set-titles-string "#{pane_title}"
        set -g window-status-format "#I:#{b:pane_current_path}/#{pane_current_command}"
        set -g window-status-current-format "#[fg=colour255,bg=colour24,bold] #I:#{b:pane_current_path}/#{pane_current_command} #[default]"

        # プレフィックスなしで直接使えるキーバインド

        # ctrl+o = 新規ウィンドウ(タブ)、同じディレクトリで開始
        bind -n C-o new-window -a -c "#{pane_current_path}"

        # ctrl+q = ウィンドウを閉じる
        bind -n C-q confirm-before -p "kill window? (y/n)" kill-window

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
        # F12でネストされた内側のtmuxを優先操作するトグル
        bind -T root F12 \
          set prefix None \;\
          set key-table off \;\
          set status-style "bg=colour238" \;\
          if -F '#{pane_in_mode}' 'send-keys -X cancel' \;\
          refresh-client -S
        bind -T off F12 \
          set -u prefix \;\
          set -u key-table \;\
          set -u status-style \;\
          refresh-client -S

        # tmux-resurrect/continuum
        set -g @continuum-restore 'on'
        set -g @resurrect-capture-pane-contents 'on'
      '';
    };
  };
}
