{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  inputs,
  osConfig ? null,
  ...
}:
let
  ccstatusline = pkgs.callPackage ../../pkgs/ccstatusline.nix { };

  # flake input経由でkonokaプラグインを取得します。
  # ユーザレベルのプラグインはClaude Codeのmarketplace経由ではなく、
  # ビルド済みプラグインを直接読み込みます。
  konokaPlugins = inputs.konoka.packages.${pkgs.stdenv.hostPlatform.system};

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
    package = pkgs-unstable.claude-code;

    # `CLAUDE.md`と同等です。
    context = config.prompt.codingAgent;

    # `mcp.nix`と連携します。
    enableMcpIntegration = true;

    # ビルド済みのプラグインパッケージを直接リンクします。
    plugins = with konokaPlugins; [
      commit
      haskell-tasuke
      kyosei
      log-analyzer
      nix-tasuke
      pr
      programming-tasuke
      proofreading-ja
      research
      rm-to-trash
      web-tasuke
    ];

    settings = {
      # 応答に使う自然言語です。
      language = "japanese";
      # 常にフルの表示を要求します。
      verbose = true;
      # 頻繁に最適な値が変わるので設定するその時に最適なものを選びます。
      # 通常はモデルのバージョンは指定せずその時の最新を優先するのですが、
      # opus-4.8があまりにも酷く、
      # 統合失調症のように幻聴を聞き続けるので、
      # fableをデフォルトに、
      # フォールバックの筆頭に緊急回避としてopus-4.7を指定します。
      # 新しいモデルがリリースされたらまた考え直します。
      model = "fable";
      fallbackModel = [
        "claude-opus-4-7"
        "opus"
        "sonnet"
      ];
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
      };
      # pluginを記述しておくことで起動時にインストールされていない場合自動でインストールされます。
      enabledPlugins = {
        ## lsp plugin
        "clangd-lsp@claude-plugins-official" = true;
        "gopls-lsp@claude-plugins-official" = true;
        "pyright-lsp@claude-plugins-official" = true;
        "rust-analyzer-lsp@claude-plugins-official" = true;
        "typescript-lsp@claude-plugins-official" = true;
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
        allow = [
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
          "mcp__plugin_claude-code-home-manager_context7"
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
}
