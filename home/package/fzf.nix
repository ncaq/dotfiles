{ pkgs, ... }:
let
  # Emacs htnsbf風キーバインドを再現
  # `FZF_DEFAULT_OPTS`に`<`や`>`を含むバインドを入れるとシェルのリダイレクト記号として解釈されます
  # `FZF_DEFAULT_OPTS_FILE`はシェルの解釈を受けませんが、fzf自体が`<`と`>`を特殊文字として扱うためバックスラッシュエスケープが必要です
  fzfDefaultOptsFile = pkgs.writeText "fzf-default-opts" ''
    --bind=ctrl-g:abort,ctrl-j:accept
    --bind=ctrl-v:page-down,alt-v:page-up
    --bind=ctrl-t:up,ctrl-n:down
    --bind=ctrl-h:backward-char,ctrl-s:forward-char
    --bind=ctrl-b:backward-delete-char
    --bind=alt-h:backward-word,alt-s:forward-word
    --bind=alt-b:backward-kill-word
    --bind=alt-\<:first,alt-\>:last
    --reverse
    --border
  '';
in
{
  programs.fzf = {
    enable = true;

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

  home.sessionVariables.FZF_DEFAULT_OPTS_FILE = "${fzfDefaultOptsFile}";
}
