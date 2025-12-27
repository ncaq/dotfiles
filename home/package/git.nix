{ inputs, ... }:
{
  imports = [ inputs.git-hooks.modules.homeManager.default ];
  programs = {
    git = {
      enable = true;
      lfs.enable = true;
      settings = {
        user = {
          name = "ncaq";
          email = "ncaq@ncaq.net";
        };
        color.ui = true;
        core = {
          autocrlf = false;
          editor = "emacsclient";
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
    gh.enable = true;
    git-hooks.enable = true;
  };
}
