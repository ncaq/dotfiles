{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  osConfig ? null,
  ...
}:
let
  # Claude Codeのパッケージをsopsシークレットから環境変数を注入するラッパーで包む。
  # `api.githubcopilot.com`がOAuth Dynamic Client Registrationをサポートしないのと、
  # それを正しくClaude Codeが処理しないため、
  # PATをBearer tokenとしてHTTPヘッダーで渡す必要があります。
  # 全シェルにトークンを展開するのはあまりやりたくないため、
  # コマンドだけに注入する方法を取ります。
  # `symlinkJoin`+`wrapProgram`ではなく`writeShellApplication`を使うことで、
  # home-managerの`--mcp-config`ラッピングと合わせた二重wrappingを避けて、
  # プロセスの名前を`claude`に保ちます。
  claude-code-wrapped = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      if [[ -r ${config.sops.secrets."github-mcp-server/pat".path} ]]; then
        GITHUB_PERSONAL_ACCESS_TOKEN="$(< ${config.sops.secrets."github-mcp-server/pat".path})"
        export GITHUB_PERSONAL_ACCESS_TOKEN
      fi
      exec ${lib.getExe pkgs-unstable.claude-code} "$@"
    '';
  };

  ccstatusline = pkgs.callPackage ../../pkgs/ccstatusline.nix { };

  backlog-mcp-server = pkgs.callPackage ../../pkgs/backlog-mcp-server.nix { };
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

  # npm, yarn, pnpm, bunで共通のサブコマンドを許可するためのヘルパー
  jsPackageManagers = [
    "npm"
    "yarn"
    "pnpm"
    "bun"
  ];

  # 直接実行するサブコマンド (install等)
  jsDirectSubcommands = [
    "ci:*"
    "info:*"
    "install:*"
    "ls:*"
    "view:*"
  ];

  # npm run経由で実行するサブコマンド (npmは `npm run <cmd>` 形式、他は `<pkg> <cmd>` 形式)
  jsRunSubcommands = [
    "build:*"
    "dev:*"
    "fix:*"
    "lint:*"
    "lint:eslint"
    "lint:prettier"
    "lint:tsc"
    "npm:*"
    "prettier:*"
    "preview:*"
    "test:*"
  ];

  mkJsDirectPermissions = pkg: map (sub: "Bash(${pkg} ${sub})") jsDirectSubcommands;

  mkJsRunPermissions =
    pkg:
    let
      prefix = if pkg == "npm" then "${pkg} run" else pkg;
    in
    map (sub: "Bash(${prefix} ${sub})") jsRunSubcommands;

  jsRunnerPermissions = lib.concatMap (
    pkg: mkJsDirectPermissions pkg ++ mkJsRunPermissions pkg
  ) jsPackageManagers;

  # コーディングエージェントの作業ディレクトリ。
  # konokaプラグインは`${XDG_RUNTIME_DIR:-/tmp}/coding-agent-work/`を使用します。
  # NixOS環境では`osConfig`からUIDを取得して、
  # `/run/user/<uid>/coding-agent-work/`を構築します。
  # 非NixOS環境(Termux等)では`XDG_RUNTIME_DIR`が設定されない場合があるため、
  # `/tmp`にフォールバックします。
  codingAgentWorkDirFullPath =
    let
      uid = if osConfig != null then osConfig.users.users.${config.home.username}.uid else null;
      base = if uid != null then "/run/user/${toString uid}" else "/tmp";
    in
    "${base}/coding-agent-work/";
in
{
  programs.claude-code = {
    enable = true;
    package = claude-code-wrapped;

    # `CLAUDE.md`と同等です。
    context = config.prompt.codingAgent;

    mcpServers = {
      github = {
        type = "http";
        url = "https://api.githubcopilot.com/mcp/";
        headers = {
          Authorization = "Bearer \${GITHUB_PERSONAL_ACCESS_TOKEN}";
        };
      };
      deepwiki = {
        type = "http";
        url = "https://mcp.deepwiki.com/mcp";
      };
      backlog = {
        type = "stdio";
        command = lib.getExe backlog-mcp-server-wrapper;
      };
    };

    settings = {
      # 応答に使う自然言語です。
      language = "japanese";
      # 設定時に最適な値を切り替えていきます。
      model = "opus[1m]";
      # メッセージにCo-Authored-Byフッターを付与しません。
      # 私はAIエージェントはテキストエディタの延長線上だと考えているため、
      # ツール名が書かれるのは不自然だと思っています。
      attribution = {
        commit = "";
        pr = "";
      };
      # グローバルに有効なhookを設定します。
      hooks = {
        SessionStart = [
          {
            matcher = "startup|clear"; # resume時はもう知っているはずなので除外。
            hooks = [
              # もうサーバで動いているのにサーバにsshしようとしたり、
              # 使っているOSに合わないコマンドを実行しようとしたりするのを防ぐために、
              # 起動時にfastfetchで環境情報を表示します。
              {
                type = "command";
                command = ''
                  cat <<'EOS'
                  以下の情報はfastfetchの実行結果です。
                  今どのようなマシンで動いているか、
                  そのマシンが起動時にどのような状態にあるかを示しています。
                  特に一行目のユーザ名の`@`の右に書いてあるhostnameと、
                  OSの情報を覚えてください。
                  EOS
                  ${pkgs.fastfetch}/bin/fastfetch
                '';
              }
            ];
          }
        ];
      };
      # ちらつきが少ないことが期待できる表示方法を選びます。
      tui = "fullscreen";
      # statuslineを設定します。
      # ccstatuslineを使用して豪華な表示にします。
      statusLine = {
        type = "command";
        command = lib.getExe ccstatusline;
      };
      inputNeededNotifEnabled = true; # 入力待ちのときに通知を出す。
      sandbox = {
        # sandboxは通常無効にします。
        # sandboxであることが由来のトラブルが多すぎるためです。
        enabled = false;
        # sandboxを有効にしたときはサンドボックスを抜けるのを許可しません。
        # sandboxを有効にしたいときはsandbox任せで自動承認させたいと思う時が多いからです。
        allowUnsandboxedCommands = false;
      };
      extraKnownMarketplaces = {
        # インストール時にclaude-plugins-officialは登録されますが、
        # ファイルが消えると再登録されないため宣言的に追加もしておきます。
        claude-plugins-official = {
          source = {
            source = "github";
            repo = "anthropics/claude-plugins-official";
          };
        };
        konoka = {
          source = {
            source = "github";
            repo = "ncaq/konoka";
            ref = "v8.3.0";
          };
        };
        context7-marketplace = {
          source = {
            source = "github";
            repo = "upstash/context7";
            ref = "@upstash/context7-mcp@2.2.5";
          };
        };
      };
      # pluginを記述しておくことで起動時にインストールされていない場合自動でインストールされます。
      enabledPlugins = {
        # claude-plugins-official
        "plugin-dev@claude-plugins-official" = true;
        ## lsp plugin
        "clangd-lsp@claude-plugins-official" = true;
        "csharp-lsp@claude-plugins-official" = true;
        "gopls-lsp@claude-plugins-official" = true;
        "jdtls-lsp@claude-plugins-official" = true;
        "kotlin-lsp@claude-plugins-official" = true;
        "lua-lsp@claude-plugins-official" = true;
        "pyright-lsp@claude-plugins-official" = true;
        "ruby-lsp@claude-plugins-official" = true;
        "rust-analyzer-lsp@claude-plugins-official" = true;
        "swift-lsp@claude-plugins-official" = true;
        "typescript-lsp@claude-plugins-official" = true;
        # konoka
        "commit@konoka" = true;
        "haskell-tasuke@konoka" = true;
        "kyosei@konoka" = true;
        "log-analyzer@konoka" = true;
        "nix-tasuke@konoka" = true;
        "pr@konoka" = true;
        "programming-tasuke@konoka" = true;
        "proofreading-ja@konoka" = true;
        "research@konoka" = true;
        "rm-to-trash@konoka" = true;
        "web-tasuke@konoka" = true;
        # Context7
        "context7-plugin@context7-marketplace" = true; # ライブラリドキュメント検索
      };
      skipAutoPermissionPrompt = true; # auto modeをdefaultModeにしているので許可を求めない。
      permissions = {
        defaultMode = "auto";
        additionalDirectories = [
          # コーディングエージェント向けに用意した作業ディレクトリは当然読み書きを許可します。
          codingAgentWorkDirFullPath
          # nixのビルド結果の`result`はシンボリックリンクで`/nix/store/`を見ているので、
          # ビルド結果を参照する時いちいち許可を求められないようにします。
          # トラブル時にプログラムのソースコードを探る時もここから読むので、
          # 調査時にも許可を求められないようにします。
          # ファイルシステムレベルで読み取り専用なので壊される心配はありません。
          "/nix/store/"
          # dotfilesにグローバルの設定の殆どを置いているので、
          # 現在の設定を確認しやすいように読み取りを許可します。
          # 書き込みも許可してしまいますが、
          # 適切に拒否するのが面倒なのでそのままにしています。
          "~/dotfiles/"
        ];
        allow = jsRunnerPermissions ++ [
          "Bash($EDITOR:*)"
          "Bash(* --help *)"
          "Bash(* --version)"
          "Bash(awk:*)"
          "Bash(cat:*)"
          "Bash(chmod:*)"
          "Bash(coredumpctl:*)"
          "Bash(curl:*)"
          "Bash(diff:*)"
          "Bash(dig:*)"
          "Bash(direnv:*)"
          "Bash(docker:*)"
          "Bash(echo:*)"
          "Bash(env)"
          "Bash(fastfetch:*)"
          "Bash(fd:*)"
          "Bash(find:*)"
          "Bash(getent:*)"
          "Bash(gh * browse:*)"
          "Bash(gh * check:*)"
          "Bash(gh * checkout:*)"
          "Bash(gh * checks:*)"
          "Bash(gh * clone:*)"
          "Bash(gh * diff:*)"
          "Bash(gh * download:*)"
          "Bash(gh * get:*)"
          "Bash(gh * list:*)"
          "Bash(gh * logs:*)"
          "Bash(gh * ports:*)"
          "Bash(gh * search:*)"
          "Bash(gh * status:*)"
          "Bash(gh * verify:*)"
          "Bash(gh * view:*)"
          "Bash(gh * watch:*)"
          "Bash(gh attestation trusted-root:*)"
          "Bash(gh browse:*)"
          "Bash(gh completion:*)"
          "Bash(gh repo gitignore:*)"
          "Bash(gh repo license:*)"
          "Bash(gh search:*)"
          "Bash(gh status:*)"
          "Bash(git -C * add *)"
          "Bash(git -C * diff *)"
          "Bash(git -C * log *)"
          "Bash(git -C * show *)"
          "Bash(git -C * status *)"
          "Bash(git add:*)"
          "Bash(git checkout:*)"
          "Bash(git clone:*)"
          "Bash(git diff:*)"
          "Bash(git fetch:*)"
          "Bash(git log:*)"
          "Bash(git ls-files:*)"
          "Bash(git ls-remote:*)"
          "Bash(git ls-tree:*)"
          "Bash(git mv:*)"
          "Bash(git restore:*)"
          "Bash(git show-branch:*)"
          "Bash(git show:*)"
          "Bash(git stash:*)"
          "Bash(git status:*)"
          "Bash(git switch:*)"
          "Bash(grep:*)"
          "Bash(hadolint:*)"
          "Bash(hash:*)"
          "Bash(hostname)"
          "Bash(hostnamectl status:*)"
          "Bash(infocmp:*)"
          "Bash(ip:*)"
          "Bash(journalctl:*)"
          "Bash(jq:*)"
          "Bash(ln:*)"
          "Bash(localectl status:*)"
          "Bash(ls:*)"
          "Bash(mkdir:*)"
          "Bash(mktemp:*)"
          "Bash(mount)"
          "Bash(networkctl status:*)"
          "Bash(nix build:*)"
          "Bash(nix copy:*)"
          "Bash(nix derivation show:*)"
          "Bash(nix eval:*)"
          "Bash(nix flake check:*)"
          "Bash(nix flake info:*)"
          "Bash(nix flake lock:*)"
          "Bash(nix flake metadata:*)"
          "Bash(nix flake prefetch:*)"
          "Bash(nix flake show:*)"
          "Bash(nix fmt:*)"
          "Bash(nix hash:*)"
          "Bash(nix log:*)"
          "Bash(nix path-info:*)"
          "Bash(nix search:*)"
          "Bash(nix store:*)"
          "Bash(nix why-depends:*)"
          "Bash(nix-diff:*)"
          "Bash(nix-fast-build:*)"
          "Bash(nix-init:*)"
          "Bash(nix-prefetch-bzr:*)"
          "Bash(nix-prefetch-cvs:*)"
          "Bash(nix-prefetch-docker:*)"
          "Bash(nix-prefetch-git:*)"
          "Bash(nix-prefetch-github:*)"
          "Bash(nix-prefetch-hg:*)"
          "Bash(nix-prefetch-svn:*)"
          "Bash(nix-prefetch:*)"
          "Bash(nix-update:*)"
          "Bash(nixos-option:*)"
          "Bash(nslookup:*)"
          "Bash(nurl:*)"
          "Bash(ping:*)"
          "Bash(prefetch-npm-deps:*)"
          "Bash(prefetch-yarn-deps:*)"
          "Bash(prettier:*)"
          "Bash(printenv:*)"
          "Bash(printf:*)"
          "Bash(readlink:*)"
          "Bash(rg:*)"
          "Bash(sops --encrypt:*)"
          "Bash(sort:*)"
          "Bash(ss:*)"
          "Bash(systemctl * cat *)"
          "Bash(systemctl * list-units *)"
          "Bash(systemctl * show *)"
          "Bash(systemctl * status *)"
          "Bash(systemd-analyze:*)"
          "Bash(tailscale status:*)"
          "Bash(tee:*)"
          "Bash(timedatectl status:*)"
          "Bash(touch:*)"
          "Bash(trash:*)"
          "Bash(tree:*)"
          "Bash(true)"
          "Bash(update-nix-fetchgit:*)"
          "Bash(wc:*)"
          "WebFetch"
          "WebSearch"
          "mcp__plugin_claude-code-home-manager_backlog__count_issues"
          "mcp__plugin_claude-code-home-manager_backlog__count_notifications"
          "mcp__plugin_claude-code-home-manager_backlog__get_categories"
          "mcp__plugin_claude-code-home-manager_backlog__get_custom_fields"
          "mcp__plugin_claude-code-home-manager_backlog__get_document"
          "mcp__plugin_claude-code-home-manager_backlog__get_document_tree"
          "mcp__plugin_claude-code-home-manager_backlog__get_documents"
          "mcp__plugin_claude-code-home-manager_backlog__get_git_repositories"
          "mcp__plugin_claude-code-home-manager_backlog__get_git_repository"
          "mcp__plugin_claude-code-home-manager_backlog__get_issue"
          "mcp__plugin_claude-code-home-manager_backlog__get_issue_comments"
          "mcp__plugin_claude-code-home-manager_backlog__get_issue_types"
          "mcp__plugin_claude-code-home-manager_backlog__get_issues"
          "mcp__plugin_claude-code-home-manager_backlog__get_myself"
          "mcp__plugin_claude-code-home-manager_backlog__get_notifications"
          "mcp__plugin_claude-code-home-manager_backlog__get_priorities"
          "mcp__plugin_claude-code-home-manager_backlog__get_project"
          "mcp__plugin_claude-code-home-manager_backlog__get_project_list"
          "mcp__plugin_claude-code-home-manager_backlog__get_pull_request"
          "mcp__plugin_claude-code-home-manager_backlog__get_pull_request_comments"
          "mcp__plugin_claude-code-home-manager_backlog__get_pull_requests"
          "mcp__plugin_claude-code-home-manager_backlog__get_pull_requests_count"
          "mcp__plugin_claude-code-home-manager_backlog__get_resolutions"
          "mcp__plugin_claude-code-home-manager_backlog__get_space"
          "mcp__plugin_claude-code-home-manager_backlog__get_users"
          "mcp__plugin_claude-code-home-manager_backlog__get_version_milestone_list"
          "mcp__plugin_claude-code-home-manager_backlog__get_watching_list_count"
          "mcp__plugin_claude-code-home-manager_backlog__get_watching_list_items"
          "mcp__plugin_claude-code-home-manager_backlog__get_wiki"
          "mcp__plugin_claude-code-home-manager_backlog__get_wiki_pages"
          "mcp__plugin_claude-code-home-manager_backlog__get_wikis_count"
          "mcp__plugin_claude-code-home-manager_deepwiki"
          "mcp__plugin_claude-code-home-manager_github__get_commit"
          "mcp__plugin_claude-code-home-manager_github__get_file_contents"
          "mcp__plugin_claude-code-home-manager_github__get_label"
          "mcp__plugin_claude-code-home-manager_github__get_latest_release"
          "mcp__plugin_claude-code-home-manager_github__get_me"
          "mcp__plugin_claude-code-home-manager_github__get_release_by_tag"
          "mcp__plugin_claude-code-home-manager_github__get_tag"
          "mcp__plugin_claude-code-home-manager_github__get_team_members"
          "mcp__plugin_claude-code-home-manager_github__get_teams"
          "mcp__plugin_claude-code-home-manager_github__issue_read"
          "mcp__plugin_claude-code-home-manager_github__list_branches"
          "mcp__plugin_claude-code-home-manager_github__list_commits"
          "mcp__plugin_claude-code-home-manager_github__list_issue_types"
          "mcp__plugin_claude-code-home-manager_github__list_issues"
          "mcp__plugin_claude-code-home-manager_github__list_pull_requests"
          "mcp__plugin_claude-code-home-manager_github__list_releases"
          "mcp__plugin_claude-code-home-manager_github__list_tags"
          "mcp__plugin_claude-code-home-manager_github__pull_request_read"
          "mcp__plugin_claude-code-home-manager_github__search_code"
          "mcp__plugin_claude-code-home-manager_github__search_issues"
          "mcp__plugin_claude-code-home-manager_github__search_pull_requests"
          "mcp__plugin_claude-code-home-manager_github__search_repositories"
          "mcp__plugin_claude-code-home-manager_github__search_users"
          "mcp__plugin_context7-plugin_context7"
          "mcp__plugin_nix-tasuke_nixos"
        ];
        ask = [
          "Bash(docker compose rm:*)"
          "Bash(docker config:*)"
          "Bash(docker container rm:*)"
          "Bash(docker context:*)"
          "Bash(docker exec:*)"
          "Bash(docker image rm:*)"
          "Bash(docker login:*)"
          "Bash(docker logout:*)"
          "Bash(docker network rm:*)"
          "Bash(docker node:*)"
          "Bash(docker plugin:*)"
          "Bash(docker push:*)"
          "Bash(docker rm:*)"
          "Bash(docker rmi:*)"
          "Bash(docker run:*)"
          "Bash(docker secret:*)"
          "Bash(docker service:*)"
          "Bash(docker stack:*)"
          "Bash(docker swarm:*)"
          "Bash(docker trust:*)"
          "Bash(docker volume rm:*)"
        ];
        deny = [
          "Bash(gh * delete:*)"
          "Bash(gh repo archive:*)"
          "Bash(gh repo rename:*)"
          "Bash(git rm:*)"
          "Bash(rm:*)"
        ];
      };
    };
  };

  home = {
    # Claude Codeがnativeインストール時に`~/.local/bin/claude`が存在していないと警告を出すため、
    # シンボリックリンクを作成して警告を抑制します。
    file.".local/bin/claude".source = "${config.programs.claude-code.finalPackage}/bin/claude";

    activation = {
      # `~/.claude.json`に書き込まれる設定をインストール時に設定。
      # `settings.json`では設定できません。
      mergeClaudeJson =
        let
          claudeJsonOverrides = {
            # Chromeを使っていないので無効にします。
            claudeInChromeDefaultEnabled = false;
            # 外部エディタでプロンプトを編集するとき最後の応答がエディタに表示される。
            externalEditorContext = true;
            # 起動時にリモートコントロールを有効にする。
            remoteControlAtStartup = true;
          };
          overrideJson = pkgs.writeText "overrides.json" (builtins.toJSON claudeJsonOverrides);
        in
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          CLAUDE_JSON="$HOME/.claude.json"
          # Claude Codeの設定が存在していない場合はマージせずに終了します。
          # 初回起動時にClaude Code自身がファイルを生成します。
          if [ ! -f "$CLAUDE_JSON" ]; then
            echo "Claude Code config not found at $CLAUDE_JSON, skipping merge."
            exit 0
          fi

          # jqを使ってマージします。
          if ! MERGED=$(${pkgs.jq}/bin/jq \
            -S --slurpfile overrides ${overrideJson} '. * $overrides[0]' "$CLAUDE_JSON"); then
            # マージが失敗したらエラーを出して終了します。
            echo "Failed to merge Claude Code config, invalid JSON format."
            exit 1
          fi

          CURRENT=$(${pkgs.jq}/bin/jq -S . "$CLAUDE_JSON")

          # マージ結果と既存の内容が同じならスキップ。
          if [ "$MERGED" = "$CURRENT" ]; then
            # スキップするのは何事もないときなので特にメッセージは出力しません。
            exit 0
          fi

          # 書き込みを行います。
          echo "$MERGED" \
            | $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 /dev/stdin "$CLAUDE_JSON"

          echo "merged $CLAUDE_JSON"
        '';
    }
    //
      # dotfilesの編集に常に参考にするリポジトリをDesktopにクローンしておきます。
      builtins.listToAttrs (
        let
          cloneGitHubRepo =
            { owner, name }:
            lib.nameValuePair name (
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                if [ ! -d "${config.home.homeDirectory}/Desktop/${name}" ]; then
                  $DRY_RUN_CMD ${pkgs.git}/bin/git clone --depth=50 \
                    https://github.com/${owner}/${name}.git \
                    "${config.home.homeDirectory}/Desktop/${name}"
                fi
              ''
            );
        in
        [
          (cloneGitHubRepo {
            owner = "NixOS";
            name = "nixpkgs";
          })
          (cloneGitHubRepo {
            owner = "nix-community";
            name = "home-manager";
          })
          (cloneGitHubRepo {
            owner = "ncaq";
            name = "infra.ncaq.net";
          })
        ]
      );
  };

  sops.secrets = {
    # GitHub MCP Server用のPersonal Access Tokenをsops-nixで管理します。
    # シークレットファイルは `sops secrets/github-mcp-server.yaml` で編集してください。
    # 形式:
    # pat: ghp_xxxxxxxxxxxxxxxxxxxxx
    "github-mcp-server/pat" = {
      sopsFile = ../../secrets/github-mcp-server.yaml;
      key = "pat";
      mode = "0400";
    };
    # Backlog MCP Server用の認証情報をsops-nixで管理します。
    # シークレットファイルは `sops secrets/backlog-mcp-server.yaml` で編集してください。
    # 形式:
    # domain: your-space.backlog.com
    # api-key: your-api-key
    "backlog-mcp-server/domain" = {
      sopsFile = ../../secrets/backlog-mcp-server.yaml;
      key = "domain";
      mode = "0400";
    };
    "backlog-mcp-server/api-key" = {
      sopsFile = ../../secrets/backlog-mcp-server.yaml;
      key = "api-key";
      mode = "0400";
    };
  };
}
