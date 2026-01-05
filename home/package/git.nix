{
  inputs,
  hostName ? null,
  ...
}:
let
  # 各端末ごとの署名鍵マッピング。
  # ホスト一覧にあるvanitasは仮想環境で検証をするためのものなの署名鍵は不要。
  signingKeys = {
    bullet = "33F5EB0E553A2EFB";
    creep = "60635905E8D66388";
    seminar = "562EE3E571A37489";
    SSD0086 = "B3630E320567F75A";
  };
  signingKey = signingKeys.${hostName} or null;
in
{
  imports = [ inputs.git-hooks.modules.homeManager.default ];
  programs = {
    git = {
      enable = true;
      lfs.enable = true;
      signing = {
        key = signingKey;
        signByDefault = signingKey != null;
      };
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
