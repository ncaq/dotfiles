{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  ...
}:
let
  ccstatusline = pkgs.callPackage ../../pkg/ccstatusline.nix { };

  # GitHub MCP ServerのPATをsops-nixで管理されたシークレットから読み込むラッパー
  github-mcp-server-wrapper = pkgs.writeShellApplication {
    name = "github-mcp-server-wrapper";
    runtimeInputs = [ pkgs.github-mcp-server ];
    text = ''
      if [[ -r ${config.sops.secrets."github-mcp-server/pat".path} ]]; then
        GITHUB_PERSONAL_ACCESS_TOKEN="$(< ${config.sops.secrets."github-mcp-server/pat".path})"
        export GITHUB_PERSONAL_ACCESS_TOKEN
      fi
      exec github-mcp-server "$@"
    '';
  };

  backlog-mcp-server = pkgs.callPackage ../../pkg/backlog-mcp-server.nix { };
  # Backlog MCP Serverの認証情報をsops-nixで管理されたシークレットから読み込むラッパー
  backlog-mcp-server-wrapper = pkgs.writeShellApplication {
    name = "backlog-mcp-server-wrapper";
    runtimeInputs = [ backlog-mcp-server ];
    text = ''
      if [[ -r ${config.sops.secrets."backlog-mcp-server/domain".path} ]]; then
        BACKLOG_DOMAIN="$(< ${config.sops.secrets."backlog-mcp-server/domain".path})"
        export BACKLOG_DOMAIN
      fi
      if [[ -r ${config.sops.secrets."backlog-mcp-server/api-key".path} ]]; then
        BACKLOG_API_KEY="$(< ${config.sops.secrets."backlog-mcp-server/api-key".path})"
        export BACKLOG_API_KEY
      fi
      exec backlog-mcp-server "$@"
    '';
  };

  mcp-proxy-for-aws = pkgs.callPackage ../../pkg/mcp-proxy-for-aws.nix { };
  gcloud-mcp = pkgs.callPackage ../../pkg/gcloud-mcp.nix { };
  azure-mcp = pkgs.callPackage ../../pkg/azure-mcp.nix { };

  # npm, yarn, pnpm, bunで共通のサブコマンドを許可するためのヘルパー
  jsPackageManagers = [
    "npm"
    "yarn"
    "pnpm"
    "bun"
  ];

  # 直接実行するサブコマンド (install等)
  jsDirectSubcommands = [
    "install"
    "view *"
  ];

  # npm run経由で実行するサブコマンド (npmは `npm run <cmd>` 形式、他は `<pkg> <cmd>` 形式)
  jsRunSubcommands = [
    "build *"
    "dev *"
    "fix *"
    "lint *"
    "lint:eslint"
    "lint:prettier"
    "lint:tsc"
    "prettier *"
    "preview *"
    "test *"
  ];

  mkJsDirectPermissions = pkg: map (sub: "Bash(${pkg} ${sub})") jsDirectSubcommands;

  mkJsRunPermissions =
    pkg:
    map (sub: if pkg == "npm" then "Bash(npm run ${sub})" else "Bash(${pkg} ${sub})") jsRunSubcommands;

  jsRunnerPermissions = lib.concatMap (
    pkg: mkJsDirectPermissions pkg ++ mkJsRunPermissions pkg
  ) jsPackageManagers;
in
{
  programs.claude-code = {
    enable = true;
    package = pkgs-unstable.claude-code-bin;

    # `CLAUDE.md`と同等です。
    memory.text = config.prompt.codingAgent;

    agentsDir = ../prompt/agents;
    commandsDir = ../prompt/commands;

    mcpServers = {
      playwright = {
        type = "stdio";
        command = lib.getExe pkgs.playwright-mcp;
      };
      github = {
        type = "stdio";
        command = lib.getExe github-mcp-server-wrapper;
        args = [ "stdio" ];
      };
      deepwiki = {
        type = "http";
        url = "https://mcp.deepwiki.com/mcp";
      };
      backlog = {
        type = "stdio";
        command = lib.getExe backlog-mcp-server-wrapper;
      };
      nixos = {
        type = "stdio";
        command = lib.getExe pkgs.mcp-nixos;
      };
      mdn = {
        type = "http";
        url = "https://mdn-mcp-0445ad8e765a.herokuapp.com/mcp";
      };
      cloudflare-docs = {
        type = "http";
        url = "https://docs.mcp.cloudflare.com/mcp";
      };
      aws = {
        type = "stdio";
        command = lib.getExe mcp-proxy-for-aws;
        args = [ "https://aws-mcp.us-east-1.api.aws/mcp" ];
      };
      gcloud = {
        type = "stdio";
        command = lib.getExe gcloud-mcp;
      };
      azure = {
        type = "stdio";
        command = lib.getExe azure-mcp;
        args = [
          "server"
          "start"
        ];
      };
      microsoft-learn = {
        type = "http";
        url = "https://learn.microsoft.com/api/mcp";
      };
      terraform = {
        type = "stdio";
        command = lib.getExe pkgs.terraform-mcp-server;
      };
    };

    settings = {
      # 応答に使う自然言語です。
      language = "japanese";
      # その時最適なモデルをデフォルトにします。
      model = "opus";
      # コミットメッセージにCo-Authored-Byフッターを付与しません。
      # 私はAIエージェントはテキストエディタの延長線上だと考えているためツール名がコミットに残るのは不適切です。
      attribution.commit = "";
      # statuslineを設定します。
      # ccstatuslineを使用して豪華な表示にします。
      statusLine = {
        type = "command";
        command = lib.getExe ccstatusline;
      };
      permissions = {
        defaultMode = "acceptEdits";
        additionalDirectories = [
          "/nix/store/"
          "/tmp/coding-agent-work/"
          "~/dotfiles/"
        ];
        allow = jsRunnerPermissions ++ [
          "Bash(* --help *)"
          "Bash(* --version)"
          "Bash(cabal build *)"
          "Bash(cabal clean *)"
          "Bash(cabal haddock *)"
          "Bash(cabal help *)"
          "Bash(cabal info *)"
          "Bash(cabal list *)"
          "Bash(cabal repl *)"
          "Bash(cabal run *)"
          "Bash(cabal test *)"
          "Bash(cabal update *)"
          "Bash(cabal-fmt *)"
          "Bash(cabal-gild *)"
          "Bash(cargo add *)"
          "Bash(cat *)"
          "Bash(chmod *)"
          "Bash(coredumpctl *)"
          "Bash(curl *)"
          "Bash(diff *)"
          "Bash(dig *)"
          "Bash(direnv *)"
          "Bash(docker *)"
          "Bash(echo *)"
          "Bash(env)"
          "Bash(fd *)"
          "Bash(find *)"
          "Bash(gen-hie *)"
          "Bash(gh *)"
          "Bash(ghc-pkg describe *)"
          "Bash(ghc-pkg field *)"
          "Bash(ghci *)"
          "Bash(git -C * add *)"
          "Bash(git -C * diff *)"
          "Bash(git -C * log *)"
          "Bash(git -C * show *)"
          "Bash(git -C * status *)"
          "Bash(git add *)"
          "Bash(git clone *)"
          "Bash(git diff *)"
          "Bash(git fetch *)"
          "Bash(git log *)"
          "Bash(git ls-files *)"
          "Bash(git ls-remote *)"
          "Bash(git ls-tree *)"
          "Bash(git mv *)"
          "Bash(git restore *)"
          "Bash(git show *)"
          "Bash(git status *)"
          "Bash(git switch *)"
          "Bash(grep *)"
          "Bash(hadolint *)"
          "Bash(hlint *)"
          "Bash(hostname)"
          "Bash(hostnamectl status *)"
          "Bash(journalctl *)"
          "Bash(jq *)"
          "Bash(localectl status *)"
          "Bash(ls *)"
          "Bash(mkdir *)"
          "Bash(mount)"
          "Bash(nix build *)"
          "Bash(nix copy *)"
          "Bash(nix derivation show *)"
          "Bash(nix develop *)"
          "Bash(nix eval *)"
          "Bash(nix flake check *)"
          "Bash(nix flake info *)"
          "Bash(nix flake metadata *)"
          "Bash(nix flake prefetch *)"
          "Bash(nix flake show *)"
          "Bash(nix fmt *)"
          "Bash(nix hash *)"
          "Bash(nix log *)"
          "Bash(nix path-info *)"
          "Bash(nix search *)"
          "Bash(nix shell *)"
          "Bash(nix store *)"
          "Bash(nix why-depends *)"
          "Bash(nix-diff *)"
          "Bash(nix-fast-build *)"
          "Bash(nix-init *)"
          "Bash(nix-prefetch *)"
          "Bash(nix-prefetch-bzr *)"
          "Bash(nix-prefetch-cvs *)"
          "Bash(nix-prefetch-docker *)"
          "Bash(nix-prefetch-git *)"
          "Bash(nix-prefetch-github *)"
          "Bash(nix-prefetch-hg *)"
          "Bash(nix-prefetch-svn *)"
          "Bash(nix-update *)"
          "Bash(nixos-option *)"
          "Bash(nslookup *)"
          "Bash(nurl *)"
          "Bash(parallel *)"
          "Bash(prefetch-npm-deps *)"
          "Bash(prefetch-yarn-deps *)"
          "Bash(printf *)"
          "Bash(readlink *)"
          "Bash(rg *)"
          "Bash(sops --encrypt *)"
          "Bash(ss *)"
          "Bash(stack bench *)"
          "Bash(stack build *)"
          "Bash(stack clean *)"
          "Bash(stack dot *)"
          "Bash(stack exec *)"
          "Bash(stack ghci *)"
          "Bash(stack haddock *)"
          "Bash(stack hoogle *)"
          "Bash(stack list *)"
          "Bash(stack ls *)"
          "Bash(stack path *)"
          "Bash(stack repl *)"
          "Bash(stack run *)"
          "Bash(stack test *)"
          "Bash(systemctl status *)"
          "Bash(timedatectl status *)"
          "Bash(touch *)"
          "Bash(trash *)"
          "Bash(tree *)"
          "Bash(true)"
          "Bash(update-nix-fetchgit *)"
          "Bash(xargs *)"
          "Skill(nix-check *)"
          "WebFetch"
          "WebSearch"
          "mcp__azure__azureterraformbestpractices"
          "mcp__azure__bestpractices"
          "mcp__azure__bicepschema"
          "mcp__azure__cloudarchitect"
          "mcp__azure__documentation"
          "mcp__azure__quota"
          "mcp__azure__resourcehealth"
          "mcp__backlog__count_issues"
          "mcp__backlog__count_notifications"
          "mcp__backlog__get_categories"
          "mcp__backlog__get_custom_fields"
          "mcp__backlog__get_document"
          "mcp__backlog__get_document_tree"
          "mcp__backlog__get_documents"
          "mcp__backlog__get_git_repositories"
          "mcp__backlog__get_git_repository"
          "mcp__backlog__get_issue"
          "mcp__backlog__get_issue_comments"
          "mcp__backlog__get_issue_types"
          "mcp__backlog__get_issues"
          "mcp__backlog__get_myself"
          "mcp__backlog__get_notifications"
          "mcp__backlog__get_priorities"
          "mcp__backlog__get_project"
          "mcp__backlog__get_project_list"
          "mcp__backlog__get_pull_request"
          "mcp__backlog__get_pull_request_comments"
          "mcp__backlog__get_pull_requests"
          "mcp__backlog__get_pull_requests_count"
          "mcp__backlog__get_resolutions"
          "mcp__backlog__get_space"
          "mcp__backlog__get_users"
          "mcp__backlog__get_version_milestone_list"
          "mcp__backlog__get_watching_list_count"
          "mcp__backlog__get_watching_list_items"
          "mcp__backlog__get_wiki"
          "mcp__backlog__get_wiki_pages"
          "mcp__backlog__get_wikis_count"
          "mcp__cloudflare-docs"
          "mcp__deepwiki"
          "mcp__github__get_commit"
          "mcp__github__get_file_contents"
          "mcp__github__get_label"
          "mcp__github__get_latest_release"
          "mcp__github__get_me"
          "mcp__github__get_release_by_tag"
          "mcp__github__get_tag"
          "mcp__github__get_team_members"
          "mcp__github__get_teams"
          "mcp__github__issue_read"
          "mcp__github__list_branches"
          "mcp__github__list_commits"
          "mcp__github__list_issue_types"
          "mcp__github__list_issues"
          "mcp__github__list_pull_requests"
          "mcp__github__list_releases"
          "mcp__github__list_tags"
          "mcp__github__pull_request_read"
          "mcp__github__search_code"
          "mcp__github__search_issues"
          "mcp__github__search_pull_requests"
          "mcp__github__search_repositories"
          "mcp__github__search_users"
          "mcp__mdn"
          "mcp__microsoft-learn"
          "mcp__nixos"
          "mcp__playwright__browser_console_messages"
          "mcp__playwright__browser_network_requests"
          "mcp__playwright__browser_snapshot"
          "mcp__playwright__browser_take_screenshot"
          "mcp__terraform"
        ];
        ask = [
          "Bash(docker compose rm *)"
          "Bash(docker config *)"
          "Bash(docker container rm *)"
          "Bash(docker context *)"
          "Bash(docker image rm *)"
          "Bash(docker login *)"
          "Bash(docker logout *)"
          "Bash(docker network rm *)"
          "Bash(docker node *)"
          "Bash(docker plugin *)"
          "Bash(docker push *)"
          "Bash(docker rm *)"
          "Bash(docker rmi *)"
          "Bash(docker secret *)"
          "Bash(docker service *)"
          "Bash(docker stack *)"
          "Bash(docker swarm *)"
          "Bash(docker trust *)"
          "Bash(docker volume rm *)"
          "Bash(gh api *)"
          "Bash(gh auth *)"
          "Bash(gh config set *)"
          "Bash(gh extension remove *)"
          "Bash(gh issue create *)"
          "Bash(gh label delete *)"
          "Bash(gh pr merge *)"
          "Bash(gh run delete *)"
          "Bash(git commit *)"
        ];
        deny = [
          "Bash(gh gist delete *)"
          "Bash(gh issue delete *)"
          "Bash(gh project delete *)"
          "Bash(gh release delete *)"
          "Bash(gh repo archive *)"
          "Bash(gh repo delete *)"
          "Bash(gh repo rename *)"
          "Bash(rm *)"
        ];
      };
    };
  };

  # GitHub MCP Server用のPersonal Access Tokenをsops-nixで管理します。
  # シークレットファイルは `sops secrets/github-mcp-server.yaml` で編集してください。
  # 形式:
  # pat: ghp_xxxxxxxxxxxxxxxxxxxxx
  sops.secrets."github-mcp-server/pat" = {
    sopsFile = ../../secrets/github-mcp-server.yaml;
    key = "pat";
    mode = "0400";
  };

  # Backlog MCP Server用の認証情報をsops-nixで管理します。
  # シークレットファイルは `sops secrets/backlog-mcp-server.yaml` で編集してください。
  # 形式:
  # domain: your-space.backlog.com
  # api-key: your-api-key
  sops.secrets."backlog-mcp-server/domain" = {
    sopsFile = ../../secrets/backlog-mcp-server.yaml;
    key = "domain";
    mode = "0400";
  };
  sops.secrets."backlog-mcp-server/api-key" = {
    sopsFile = ../../secrets/backlog-mcp-server.yaml;
    key = "api-key";
    mode = "0400";
  };

  # Clone repositories for additionalDirectories if they don't exist
  home.activation.cloneNixpkgs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${config.home.homeDirectory}/Desktop/nixpkgs" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone --depth=50 \
        https://github.com/NixOS/nixpkgs.git \
        "${config.home.homeDirectory}/Desktop/nixpkgs"
    fi
  '';
  home.activation.cloneHomeManager = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -d "${config.home.homeDirectory}/Desktop/home-manager" ]; then
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone --depth=50 \
        https://github.com/nix-community/home-manager.git \
        "${config.home.homeDirectory}/Desktop/home-manager"
    fi
  '';
}
