{ pkgs, lib, ... }:
{
  # Claude Codeの更新頻度が高すぎるので、仕方なくnpmでインストールする。
  home.activation.setupClaudeCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${pkgs.nodejs}/bin:~/.local/bin:$PATH"
    $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm --prefix ~/.local install -g @anthropic-ai/claude-code
  '';
}
