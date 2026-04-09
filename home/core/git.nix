{
  pkgs,
  inputs,
  ...
}:
let
  keyConfig = import ../../key;
  inherit (keyConfig) identityKey;
in
{
  imports = [ inputs.git-hooks.modules.homeManager.default ];
  programs = {
    git = {
      enable = true;
      lfs.enable = true;
      signing = {
        key = identityKey;
        signByDefault = true;
      };
      settings = {
        user = {
          name = "ncaq";
          email = "ncaq@ncaq.net";
        };
        color.ui = true;
        core = {
          autocrlf = false;
          editor = "emacsclient --reuse-frame --alternate-editor=emacs";
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
    git-hooks.enable = true;

    gh.enable = true;
  };
  home.packages = with pkgs; [ zizmor ];
}
