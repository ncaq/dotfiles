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
in
{
  # GitHub MCP Server用のPersonal Access Tokenをsops-nixで管理します。
  # シークレットファイルは `sops secrets/github-mcp-server.yaml` で編集してください。
  # 形式:
  # pat: ghp_xxxxxxxxxxxxxxxxxxxxx
  sops.secrets."github-mcp-server/pat" = {
    sopsFile = ../../secrets/github-mcp-server.yaml;
    key = "pat";
  };

  # Backlog MCP Server用の認証情報をsops-nixで管理します。
  # シークレットファイルは `sops secrets/backlog-mcp-server.yaml` で編集してください。
  # 形式:
  # domain: your-space.backlog.com
  # api-key: your-api-key
  sops.secrets."backlog-mcp-server/domain" = {
    sopsFile = ../../secrets/backlog-mcp-server.yaml;
    key = "domain";
  };
  sops.secrets."backlog-mcp-server/api-key" = {
    sopsFile = ../../secrets/backlog-mcp-server.yaml;
    key = "api-key";
  };

  home.packages = [
    # Claude Codeのsandbox機能を利用する時は必要。
    pkgs.bubblewrap
    pkgs.socat
  ];

  programs.claude-code = {
    enable = true;
    package = pkgs-unstable.claude-code;

    # `CLAUDE.md`と同等です。
    memory.text = config.prompt.coding-agent;

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
      nix = {
        type = "stdio";
        command = lib.getExe pkgs.mcp-nixos;
      };
      cloudflare-docs = {
        type = "http";
        url = "https://docs.mcp.cloudflare.com/mcp";
      };
      terraform = {
        type = "stdio";
        command = lib.getExe pkgs.terraform-mcp-server;
      };
    };

    settings = {
      # その時最適なモデルをデフォルトにします。
      model = "opus";
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
        allow = [
          "Bash(atop:*)"
          "Bash(bun build:*)"
          "Bash(bun dev:*)"
          "Bash(bun fix:*)"
          "Bash(bun lint:*)"
          "Bash(bun lint:eslint)"
          "Bash(bun lint:prettier)"
          "Bash(bun lint:tsc)"
          "Bash(bun prettier:*)"
          "Bash(bun preview:*)"
          "Bash(cabal build:*)"
          "Bash(cabal clean:*)"
          "Bash(cabal haddock:*)"
          "Bash(cabal help:*)"
          "Bash(cabal info:*)"
          "Bash(cabal list:*)"
          "Bash(cabal repl:*)"
          "Bash(cabal run:*)"
          "Bash(cabal test:*)"
          "Bash(cabal update:*)"
          "Bash(cabal-fmt:*)"
          "Bash(cabal-gild:*)"
          "Bash(cargo add:*)"
          "Bash(cat:*)"
          "Bash(chmod:*)"
          "Bash(coredumpctl:*)"
          "Bash(curl:*)"
          "Bash(diff:*)"
          "Bash(dig:*)"
          "Bash(direnv:*)"
          "Bash(docker --help:*)"
          "Bash(docker --version:*)"
          "Bash(docker build:*)"
          "Bash(docker buildx bake:*)"
          "Bash(docker buildx build:*)"
          "Bash(docker buildx create:*)"
          "Bash(docker buildx du:*)"
          "Bash(docker buildx history:*)"
          "Bash(docker buildx inspect:*)"
          "Bash(docker buildx ls:*)"
          "Bash(docker buildx version:*)"
          "Bash(docker compose build:*)"
          "Bash(docker compose config:*)"
          "Bash(docker compose create:*)"
          "Bash(docker compose down:*)"
          "Bash(docker compose events:*)"
          "Bash(docker compose exec:*)"
          "Bash(docker compose images:*)"
          "Bash(docker compose kill:*)"
          "Bash(docker compose logs:*)"
          "Bash(docker compose ls:*)"
          "Bash(docker compose pause:*)"
          "Bash(docker compose port:*)"
          "Bash(docker compose ps:*)"
          "Bash(docker compose pull:*)"
          "Bash(docker compose restart:*)"
          "Bash(docker compose run:*)"
          "Bash(docker compose scale:*)"
          "Bash(docker compose start:*)"
          "Bash(docker compose stats:*)"
          "Bash(docker compose stop:*)"
          "Bash(docker compose top:*)"
          "Bash(docker compose unpause:*)"
          "Bash(docker compose up:*)"
          "Bash(docker compose version:*)"
          "Bash(docker container diff:*)"
          "Bash(docker container inspect:*)"
          "Bash(docker container logs:*)"
          "Bash(docker container ls:*)"
          "Bash(docker container port:*)"
          "Bash(docker container prune:*)"
          "Bash(docker container stats:*)"
          "Bash(docker container top:*)"
          "Bash(docker context ls:*)"
          "Bash(docker context show:*)"
          "Bash(docker cp:*)"
          "Bash(docker create:*)"
          "Bash(docker diff:*)"
          "Bash(docker events:*)"
          "Bash(docker exec:*)"
          "Bash(docker history:*)"
          "Bash(docker image history:*)"
          "Bash(docker image inspect:*)"
          "Bash(docker image ls:*)"
          "Bash(docker images:*)"
          "Bash(docker import:*)"
          "Bash(docker info:*)"
          "Bash(docker inspect:*)"
          "Bash(docker kill:*)"
          "Bash(docker load:*)"
          "Bash(docker logs:*)"
          "Bash(docker manifest inspect:*)"
          "Bash(docker network inspect:*)"
          "Bash(docker network ls:*)"
          "Bash(docker pause:*)"
          "Bash(docker plugin inspect:*)"
          "Bash(docker plugin ls:*)"
          "Bash(docker port:*)"
          "Bash(docker ps:*)"
          "Bash(docker pull:*)"
          "Bash(docker restart:*)"
          "Bash(docker run:*)"
          "Bash(docker save:*)"
          "Bash(docker search:*)"
          "Bash(docker start:*)"
          "Bash(docker stats:*)"
          "Bash(docker stop:*)"
          "Bash(docker system df:*)"
          "Bash(docker system info:*)"
          "Bash(docker tag:*)"
          "Bash(docker top:*)"
          "Bash(docker unpause:*)"
          "Bash(docker version:*)"
          "Bash(docker volume inspect:*)"
          "Bash(docker volume ls:*)"
          "Bash(echo:*)"
          "Bash(env)"
          "Bash(fd:*)"
          "Bash(find:*)"
          "Bash(gen-hie:*)"
          "Bash(gh config get:*)"
          "Bash(gh config list:*)"
          "Bash(gh copilot explain:*)"
          "Bash(gh copilot suggest:*)"
          "Bash(gh extension list:*)"
          "Bash(gh extension search:*)"
          "Bash(gh gist clone:*)"
          "Bash(gh gist list:*)"
          "Bash(gh gist view:*)"
          "Bash(gh issue list:*)"
          "Bash(gh issue status:*)"
          "Bash(gh issue view:*)"
          "Bash(gh label clone:*)"
          "Bash(gh label list:*)"
          "Bash(gh org list:*)"
          "Bash(gh pr checkout:*)"
          "Bash(gh pr checks:*)"
          "Bash(gh pr diff:*)"
          "Bash(gh pr list:*)"
          "Bash(gh pr status:*)"
          "Bash(gh pr view:*)"
          "Bash(gh project field-list:*)"
          "Bash(gh project item-list:*)"
          "Bash(gh project list:*)"
          "Bash(gh project view:*)"
          "Bash(gh release download:*)"
          "Bash(gh release list:*)"
          "Bash(gh release view:*)"
          "Bash(gh repo clone:*)"
          "Bash(gh repo license:*)"
          "Bash(gh repo list:*)"
          "Bash(gh repo view:*)"
          "Bash(gh ruleset check:*)"
          "Bash(gh ruleset list:*)"
          "Bash(gh ruleset view:*)"
          "Bash(gh run download:*)"
          "Bash(gh run list:*)"
          "Bash(gh run view:*)"
          "Bash(gh run watch:*)"
          "Bash(gh search:*)"
          "Bash(gh status:*)"
          "Bash(gh workflow list:*)"
          "Bash(gh workflow view:*)"
          "Bash(ghc-pkg describe:*)"
          "Bash(ghc-pkg field:*)"
          "Bash(ghci:*)"
          "Bash(git add:*)"
          "Bash(git clone:*)"
          "Bash(git diff:*)"
          "Bash(git fetch:*)"
          "Bash(git log:*)"
          "Bash(git ls-files:*)"
          "Bash(git ls-tree:*)"
          "Bash(git mv:*)"
          "Bash(git restore:*)"
          "Bash(git show:*)"
          "Bash(git status:*)"
          "Bash(git switch:*)"
          "Bash(grep:*)"
          "Bash(hadolint:*)"
          "Bash(hlint:*)"
          "Bash(hostname)"
          "Bash(hostnamectl status:*)"
          "Bash(iostat:*)"
          "Bash(iotop:*)"
          "Bash(journalctl:*)"
          "Bash(jq:*)"
          "Bash(localectl status:*)"
          "Bash(ls:*)"
          "Bash(mkdir:*)"
          "Bash(nix build:*)"
          "Bash(nix develop:*)"
          "Bash(nix eval:*)"
          "Bash(nix flake check:*)"
          "Bash(nix flake info:*)"
          "Bash(nix flake metadata:*)"
          "Bash(nix flake prefetch:*)"
          "Bash(nix flake show:*)"
          "Bash(nix fmt:*)"
          "Bash(nix hash:*)"
          "Bash(nix log:*)"
          "Bash(nix path-info:*)"
          "Bash(nix search:*)"
          "Bash(nix shell:*)"
          "Bash(nix why-depends:*)"
          "Bash(nix-diff:*)"
          "Bash(nix-prefetch-git:*)"
          "Bash(nix-prefetch-url:*)"
          "Bash(nixos-option:*)"
          "Bash(npm install)"
          "Bash(npm ls:*)"
          "Bash(npm run build:*)"
          "Bash(npm run dev:*)"
          "Bash(npm run fix:*)"
          "Bash(npm run lint:*)"
          "Bash(npm run lint:eslint)"
          "Bash(npm run lint:prettier)"
          "Bash(npm run lint:tsc)"
          "Bash(npm run prettier:*)"
          "Bash(npm run preview:*)"
          "Bash(npm run test:*)"
          "Bash(nslookup:*)"
          "Bash(parallel:*)"
          "Bash(pnpm build:*)"
          "Bash(pnpm dev:*)"
          "Bash(pnpm fix:*)"
          "Bash(pnpm lint:*)"
          "Bash(pnpm lint:eslint)"
          "Bash(pnpm lint:prettier)"
          "Bash(pnpm lint:tsc)"
          "Bash(pnpm prettier:*)"
          "Bash(pnpm preview:*)"
          "Bash(readlink:*)"
          "Bash(rg:*)"
          "Bash(sops --encrypt:*)"
          "Bash(ss:*)"
          "Bash(stack bench:*)"
          "Bash(stack build:*)"
          "Bash(stack clean:*)"
          "Bash(stack dot:*)"
          "Bash(stack exec:*)"
          "Bash(stack ghci:*)"
          "Bash(stack haddock:*)"
          "Bash(stack hoogle:*)"
          "Bash(stack list:*)"
          "Bash(stack ls:*)"
          "Bash(stack path:*)"
          "Bash(stack repl:*)"
          "Bash(stack run:*)"
          "Bash(stack test:*)"
          "Bash(systemctl status:*)"
          "Bash(timedatectl status:*)"
          "Bash(top:*)"
          "Bash(touch:*)"
          "Bash(trash:*)"
          "Bash(tree:*)"
          "Bash(true)"
          "Bash(xargs:*)"
          "Bash(yarn build:*)"
          "Bash(yarn dev:*)"
          "Bash(yarn fix:*)"
          "Bash(yarn lint:*)"
          "Bash(yarn lint:eslint)"
          "Bash(yarn lint:prettier)"
          "Bash(yarn lint:tsc)"
          "Bash(yarn prettier:*)"
          "Bash(yarn preview:*)"
          "WebFetch"
          "WebSearch"
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
          "mcp__deepwiki__ask_question"
          "mcp__deepwiki__read_wiki_contents"
          "mcp__deepwiki__read_wiki_structure"
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
          "mcp__nix__darwin_info"
          "mcp__nix__darwin_list_options"
          "mcp__nix__darwin_options_by_prefix"
          "mcp__nix__darwin_search"
          "mcp__nix__darwin_stats"
          "mcp__nix__home_manager_info"
          "mcp__nix__home_manager_list_options"
          "mcp__nix__home_manager_options_by_prefix"
          "mcp__nix__home_manager_search"
          "mcp__nix__home_manager_stats"
          "mcp__nix__nixhub_find_version"
          "mcp__nix__nixhub_package_versions"
          "mcp__nix__nixos_channels"
          "mcp__nix__nixos_flakes_search"
          "mcp__nix__nixos_flakes_stats"
          "mcp__nix__nixos_info"
          "mcp__nix__nixos_search"
          "mcp__nix__nixos_stats"
          "mcp__playwright__browser_console_messages"
          "mcp__playwright__browser_network_requests"
          "mcp__playwright__browser_snapshot"
          "mcp__playwright__browser_take_screenshot"
          "mcp__terraform__get_latest_module_version"
          "mcp__terraform__get_latest_provider_version"
          "mcp__terraform__get_module_details"
          "mcp__terraform__get_policy_details"
          "mcp__terraform__get_provider_capabilities"
          "mcp__terraform__get_provider_details"
          "mcp__terraform__search_modules"
          "mcp__terraform__search_policies"
          "mcp__terraform__search_providers"
        ];
        deny = [
          "Bash(git commit:*)"
          "Bash(head:*)"
          "Bash(rm:*)"
          "Bash(tail:*)"
        ];
      };
    };
  };
}
