{ pkgs, ... }:
{
  programs = {
    git = {
      enable = true;
      lfs.enable = true;
      userName = "ncaq";
      userEmail = "ncaq@ncaq.net";
      extraConfig = {
        color.ui = true;
        core = {
          autocrlf = false;
          editor = "emacsclient";
          hooksPath = "~/dotfiles/git-hooks"; # TODO: Nix的に管理。
          quotePath = false;
          symlinks = true;
        };
        commit.verbose = true;
        diff.algorithm = "histogram";
        fetch.prune = true;
        init.defaultBranch = "master";
        log.date = "iso";
        pager = {
          diff = "bat";
          log = "bat";
          show = "bat";
        };
        pull = {
          prune = true;
          rebase = false;
        };
        push.default = "current";
        rerere.enabled = true;
        github.user = "ncaq";
      };
      ignores = [
        "**/.claude/settings.local.json"
        ".DS_Store"
        "Thumbs.db"
      ];
    };
    gh = {
      enable = true;
      extensions = with pkgs; [
        github-copilot-cli
      ];
    };
  };
}
