# GNU Readline の設定。
# `.inputrc`の設定でもある。
_: {
  programs.readline = {
    enable = true;

    variables = {
      editing-mode = "emacs";
    };

    bindings = {
      # Controlキーバインド。
      "\\C-b" = "backward-delete-char";
      "\\C-h" = "backward-char";
      "\\C-n" = "history-search-forward";
      "\\C-s" = "forward-char";
      "\\C-t" = "history-search-backward";

      # Altキーバインド。
      "\\eb" = "backward-kill-word";
      "\\eh" = "backward-word";
      "\\es" = "forward-word";
      "\\et" = "history-search-backward";
    };
  };
}
