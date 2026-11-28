# Claude Codeの全ホストに共通の設定。
#
# 設定を`programs.claude-code`で宣言して、
# ユーザの`~/.claude/settings.json`として展開する。
# `settings.json`では表せない種類の設定は、
# home-managerが生成するラッパプログラムの引数として渡す。
#
# このリポジトリに固有の設定はリポジトリルートの`.claude/settings.json`にあり、
# dotfilesでClaude Codeを起動している時はここの設定とマージされる。
#
# スキルに類するものの読み込みは`llm-skill.nix`にある。
{
  lib,
  pkgs,
  pkgs-unstable,
  config,
  systemdPackage,
  codingAgentDeniedCommands,
  codingAgentWorkDirFullPath,
  ...
}:
{
  programs.claude-code = {
    enable = true;
    # コーディングエージェントは更新が早くサーバも最新バージョンを要求しがちなのでunstableを使います。
    #
    # nixpkgsはネイティブバイナリを`wrapProgram`で包んで環境変数を設定しています。
    # home-managerはさらにその上を`--plugin-dir`を付けるシェルスクリプトで包み、
    # `exec -a "$0"`でargv[0]を引き継ごうとしますが、
    # exec先がシェルスクリプトだとカーネルがargv[0]をスクリプトのパスに置き換えるため、
    # 本体に届くargv[0]は`.claude-wrapped`になってしまいます。
    # tmuxの`pane_current_command`などはargv[0]を見るのでウィンドウ名が`.claude-wrapped`と表示されます。
    # nixpkgs側のラッパをバイナリラッパに差し替えると、
    # `wrapProgram`が付ける`--inherit-argv0`が実際に効いてargv[0]が本体まで届きます。
    # home-manager masterは`--plugin-dir`ラッパ自体を廃止済みなので、
    # そちらが安定版に降りてきたらこの差し替えは不要になります。
    package = pkgs-unstable.claude-code.override {
      makeShellWrapper = pkgs-unstable.makeBinaryWrapper;
    };

    # `CLAUDE.md`と同等です。
    context = config.prompt.codingAgent;

    # `mcp.nix`と連携します。
    enableMcpIntegration = true;

    settings = {
      # 応答に使う自然言語です。
      language = "japanese";
      # 常にフルの表示を要求します。
      verbose = true;
      # デフォルトモデルを設定する`model`値は、
      # 頻繁に最適な値が変わるので、
      # 設定するその時に最適なものを選びます。
      # 今は普段はOpusを使って重要なものにFableの高エフォートを使う運用にしています。
      # 現在の`model`のデフォルト値は運用と合っていてOpusなので、
      # あえて`model`は指定せず上流に任せます。
      fallbackModel = [
        "fable"
        "sonnet"
      ];
      # メッセージに全てのフッタを付与しません。
      #
      # Co-Authored-Byは付与しません。
      # 私はAIエージェントはテキストエディタの延長線上だと考えているため、
      # ツール名が書かれるのは不自然だと思っています。
      #
      # セッションURLも付与しません。
      # セッションは作業した本人にしか見えないので、
      # 他の人が読むコミットメッセージやPRに書いても意味がないためです。
      attribution = false;
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
                  ${lib.getExe config.programs.fastfetch.package}
                '';
              }
            ];
          }
        ];
      };
      # ちらつきが少ないことが期待できる表示方法を選びます。
      tui = "fullscreen";
      # statuslineを設定します。
      statusLine = {
        type = "command";
        # ccstatuslineを使用して豪華な表示にします。
        command = lib.getExe pkgs.ccstatusline;
      };
      inputNeededNotifEnabled = true; # 入力待ちのときに通知を出す。
      env = {
        # Bashツールが使うシェルを、ログインシェルのzshではなくbashにします。
        # Claudeはbashを前提にコマンドを書くので、
        # zshだとマッチしないglobがエラーになるなどの非互換でよく失敗するためです。
        # 動かないパスを渡すと黙ってログインシェルに戻るので、
        # `bash.nix`で設定しているbashをストアパスで指定します。
        CLAUDE_CODE_SHELL = lib.getExe config.programs.bash.package;
      };
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
        # marketplace名は上流の`.claude-plugin/marketplace.json`の`name`と一致させる必要があります。
        # リポジトリのスラッグ`huggingface/skills`ではありません。
        huggingface-skills = {
          source = {
            source = "github";
            repo = "huggingface/skills";
          };
        };
      };
      # pluginを記述しておくことで起動時にインストールされていない場合自動でインストールされます。
      enabledPlugins = {
        ## lsp plugin
        "clangd-lsp@claude-plugins-official" = true;
        "csharp-lsp@claude-plugins-official" = true;
        "gopls-lsp@claude-plugins-official" = true;
        "jdtls-lsp@claude-plugins-official" = true;
        "lua-lsp@claude-plugins-official" = true;
        "pyright-lsp@claude-plugins-official" = true;
        "ruby-lsp@claude-plugins-official" = true;
        "rust-analyzer-lsp@claude-plugins-official" = true;
        "swift-lsp@claude-plugins-official" = true;
        "typescript-lsp@claude-plugins-official" = true;
        ## huggingface
        "hf-cli@huggingface-skills" = true;
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
          # `execute`はCloudflare APIへの書き込みもできるので許可しません。
          "mcp__plugin_claude-code-home-manager_cloudflare__docs"
          "mcp__plugin_claude-code-home-manager_cloudflare__search"
          "mcp__plugin_claude-code-home-manager_cloudflare__whoami"
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
          # `update_dashboard`は書き込みなので許可しません。
          "mcp__plugin_claude-code-home-manager_mackerel__get_alert"
          "mcp__plugin_claude-code-home-manager_mackerel__get_alert_logs"
          "mcp__plugin_claude-code-home-manager_mackerel__get_dashboard"
          "mcp__plugin_claude-code-home-manager_mackerel__get_host_metrics"
          "mcp__plugin_claude-code-home-manager_mackerel__get_monitor"
          "mcp__plugin_claude-code-home-manager_mackerel__get_service_metrics"
          "mcp__plugin_claude-code-home-manager_mackerel__get_trace"
          "mcp__plugin_claude-code-home-manager_mackerel__list_alerts"
          "mcp__plugin_claude-code-home-manager_mackerel__list_dashboards"
          "mcp__plugin_claude-code-home-manager_mackerel__list_db_query_stats"
          "mcp__plugin_claude-code-home-manager_mackerel__list_hosts"
          "mcp__plugin_claude-code-home-manager_mackerel__list_http_server_stats"
          "mcp__plugin_claude-code-home-manager_mackerel__list_monitors"
          "mcp__plugin_claude-code-home-manager_mackerel__list_services"
          "mcp__plugin_claude-code-home-manager_mackerel__list_traces"
          "mcp__plugin_claude-code-home-manager_mackerel__search_logs"
          "mcp__plugin_claude-code-home-manager_mdn"
          "mcp__plugin_claude-code-home-manager_microsoft-learn"
          "mcp__plugin_claude-code-home-manager_nixos"
          "mcp__plugin_nix-tasuke_nixos"
        ];
        deny = [
          "Bash(gh * delete*)"
          "Bash(gh repo archive:*)"
          "Bash(gh repo rename:*)"
        ]
        ++ map (command: "Bash(${command}:*)") codingAgentDeniedCommands;
      };
    };
  };

  # 制限は持たせず、
  # `systemd-cgls`や`systemctl --user status`で、
  # Claude Codeのセッション群をまとめて観察するためだけのsliceです。
  # Termuxなどsystemdの無い環境では単にスキップされます。
  systemd.user.slices.claude-code = {
    Unit.Description = "Claude Code sessions";
  };

  home = {
    # Claude Codeがnativeインストール時に`~/.local/bin/claude`が存在していないと警告を出すため、
    # シンボリックリンクを作成して警告を抑制します。
    # またその際に、暴走したセッションが他のアプリをOOM Killerに殺させないように、
    # セッションごとのメモリ制限を付けて起動するラッパを挟みます。
    file.".local/bin/claude".source = lib.getExe (
      pkgs.writeShellApplication {
        name = "claude";
        # `systemd-run`をPATH経由の偶然に頼らずNixの依存として明示します。
        # パッケージは`home/core/systemd.nix`が稼働中のsystemdに揃えて配布しています。
        runtimeInputs = [ systemdPackage ];
        text = ''
          claude=${config.programs.claude-code.finalPackage}/bin/claude
          # systemdがPID 1ではない環境(Termuxなど)ではそのまま起動します。
          if [ -d /run/systemd/system ]; then
            # `--scope`はサービスと違いsystemd-run自身の子プロセスとして実行されるため、
            # TTY・環境変数・カレントディレクトリがそのまま使えて対話TUIも問題ありません。
            # メモリ制限はセッション(scope)ごとに独立して付けます。
            # 暴走した1セッションだけがcgroup内のOOM Killerで殺され、
            # 他の正常なセッションや他のアプリは巻き添えを食いません。
            # systemdの`%`は全て物理メモリに対する割合です。
            # MemorySwapMaxはswap容量比ではないことに注意。
            # zram(物理メモリの20%、16GiB上限)の約半分を意図して10%としています。
            #
            # TasksMaxはfork bombのような暴走を小さく止めるためのものです。
            # TasksMaxの`%`はメモリと違い、システム全体のタスク数の上限に対する割合です。
            # 何も付けなくてもユーザのsystemdの`DefaultTasksMax`で15%が掛かりますが、
            # それだと数セッションが同時に暴走した時にシステム全体の上限へ届くので、5%に絞っています。
            # システム全体の上限は物理メモリに比例するので、割合にしておけばどのホストでも同じ比率になります。
            # スレッドも数えられるので、
            # コア数いっぱいの並列ビルドやテストでも届かないだろうと見積もった値です。
            # 実測した上限ではありません。
            #
            # ここへ足せるのはcgroupの制限だけです。
            # scopeは`SystemCallFilter`や`RestrictAddressFamilies`のような実行時の設定を受け付けません。
            # serviceにすれば付けられますが、
            # ユーザのsystemdがseccompを掛けるには`NoNewPrivileges`が必須で、
            # セッションの中から`sudo`を使えなくなるので見送っています。
            exec systemd-run --user --scope --quiet --collect \
              --slice=claude-code.slice \
              --same-dir \
              -p MemoryHigh=75% \
              -p MemoryMax=80% \
              -p MemorySwapMax=10% \
              -p TasksMax=5% \
              -- "$claude" "$@"
          fi
          exec "$claude" "$@"
        '';
      }
    );

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
          # home-managerは全てのactivationエントリを1つのbashスクリプトに連結するため、
          # ここでexitするとactivation全体が終了して後続のエントリが実行されません。
          # サブシェルで囲んでexitの影響をこのエントリ内に閉じ込めます。
          # `set -e`はサブシェルにも継承されるため、
          # 失敗時にactivationを中断させる`exit 1`の意図は維持されます。
          (
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
          )
        '';
    };
  };
}
