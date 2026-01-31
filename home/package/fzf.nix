{ ... }:
{
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
    ];
  };
}
