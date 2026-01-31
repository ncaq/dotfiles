_: {
  programs.fzf = {
    enable = true;

    # Emacs htnsbf風キーバインドを再現
    defaultOptions = [
      "--bind=ctrl-g:abort,ctrl-j:accept"
      "--bind=ctrl-v:page-down,alt-v:page-up"
      "--bind=alt-<:first,alt->:last"
      "--bind=ctrl-t:up,ctrl-n:down"
      "--bind=ctrl-h:backward-char,ctrl-s:forward-char"
      "--bind=ctrl-b:backward-delete-char"
      "--bind=alt-h:backward-word,alt-s:forward-word"
      "--bind=alt-b:backward-kill-word"
      "--reverse"
      "--border"
    ];

    # findの代わりにfdを使う
    defaultCommand = "fd --type f --hidden --exclude .git";

    # ファイル選択(batでプレビュー)
    fileWidgetCommand = "fd --type f --hidden --exclude .git";
    fileWidgetOptions = [
      "--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
    ];

    # ディレクトリ移動(treeでプレビュー)
    changeDirWidgetCommand = "fd --type d --hidden --exclude .git";
    changeDirWidgetOptions = [
      "--preview 'tree -C -L 2 {}'"
    ];

    # 履歴検索
    historyWidgetOptions = [
      "--exact"
    ];
  };
}
