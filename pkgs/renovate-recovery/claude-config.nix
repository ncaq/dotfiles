# `renovate-recovery`ワークフローのClaude Codeへ渡す設定一式。
#
# 普段使っているClaude Codeの設定のうち、
# CIで動かしても問題ないものだけを集めたディレクトリを作ります。
# ワークフローは`claude_args`でこのディレクトリの中身を指定します。
#
# - `plugins/`: `--plugin-dir`で読み込むkonokaのプラグイン
# - `git-hooks/`: `core.hooksPath`に指定するgitフック
# - `append-system-prompt.md`: `--append-system-prompt-file`で渡すプロンプト
# - `settings.json`: `--settings`で渡す設定
{
  lib,
  runCommand,
  writeText,
  konokaPlugins,
  git-hooks,
}:
let
  # 読み込むkonokaのプラグイン。
  # 以下の理由で除外したものはここに含めていません。
  #
  # - kyosei, misuzu: PRのレビューとその対応のためのもので、復旧の作業とは関係が無い
  # - rm-to-trash: ランナーには`trash`コマンドが無い
  # - prefer-builtin-update: 起動時にRustのビルドを走らせるフックを持つ
  # - fsharp-lsp, proofreading-ja: このリポジトリの復旧では使わない
  # - log-analyzer: スキルの`allowed-tools`が`Bash`を無制限に許可していて、
  #   下の`permissions`の許可の一覧を迂回できてしまう
  #
  # `web-tasuke`の`react-refactor-component`スキルは、
  # `allowed-tools`で`npm run`や`eslint`などを許可しています。
  # これらはリポジトリのスクリプトや設定を実行するので、
  # `nix fmt`や`./check.sh`と同じ程度の危険として受け入れます。
  # `nix`のサブコマンドは個別に許可しているだけなので、
  # 下の`permissions.deny`の危ないオプションの拒否が効きます。
  #
  # `commit`と`pr`は、
  # `commit-style`と`pr-style`のスタイルの規則と、
  # `run-commit-msg-hook`によるコミットメッセージの検査のために読み込みます。
  # コミットとPRの作成そのものは`prompt.md`の手順で行います。
  # これらのスキルが`allowed-tools`で許可するローカルでのコミットやpushは、
  # `permissions.deny`で塞いでいます。
  pluginNames = [
    "commit"
    "haskell-tasuke"
    "nix-tasuke"
    "pr"
    "programming-tasuke"
    "research"
    "web-tasuke"
  ];
  plugins = lib.getAttrs pluginNames konokaPlugins;

  # 普段のコーディングエージェント向けのプロンプトのうち、
  # 出力の書き方を決めるものだけを使います。
  # `environment/`は手元のマシンの情報なのでランナーでは誤解の元になります。
  # `coding-agent/`はスキルの使い方などが対話での利用を前提にしていて、
  # `prompt.md`の手順と食い違うため使いません。
  outputPromptDir = ../../home/prompt/output;
  outputPrompts = map (name: builtins.readFile (outputPromptDir + "/${name}")) (
    lib.attrNames (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (
        builtins.readDir outputPromptDir
      )
    )
  );
  appendSystemPrompt = writeText "append-system-prompt.md" (
    lib.concatStringsSep "\n---\n\n" outputPrompts
  );

  # nixの評価やビルドの仕組みそのものを変えるオプション。
  # 評価に環境変数を読ませたり、
  # ホストのnix-daemonにサンドボックスの外でコマンドを実行させたりできるので、
  # 許可した`nix`のサブコマンドや`./check.sh`に付けられないようにします。
  # 設定は`--<設定名>`や真偽値の`--no-<設定名>`の形でも渡せるので、
  # それらも`--`付きのフラグ名で塞ぎます。
  # `--`を付けずに設定名の一部だけで塞ぐと、
  # `git-hooks`のようなinput名を含む正当なコマンドまで拒否してしまいます。
  # 末尾に`-`を付けたものは、同じ前置きを持つ一連のフラグをまとめて塞ぎます。
  #
  # `--impure`は`check`ワークフローがNix-on-Droidのビルドに使っているので塞ぎません。
  # 環境変数を読むには評価されるコードを書き換える必要があり、
  # それは`nix fmt`や`./check.sh`がリポジトリのコードを実行するのと同じ程度の危険です。
  dangerousNixFlags = [
    "--expr"
    "--file"
    " -f "
    "--option"
    "--override"
    "--inputs-from"
    "--extra-"
    "--store"
    "--pure-eval"
    "--no-pure-eval"
    "--allow-unsafe-native-code-during-evaluation"
    # `--sandbox-paths`などもまとめて塞ぎます。
    "--sandbox"
    "--no-sandbox"
    "--build-hook"
    "--post-build-hook"
    "--pre-build-hook"
    "--diff-hook"
    "--run-diff-hook"
    # `--builders-use-substitutes`もまとめて塞ぎます。
    "--builders"
    "--substituters"
    "--trusted-"
    "--require-sigs"
    "--no-require-sigs"
  ];

  # コマンドの中で絶対パスの直前に来うる文字。
  absolutePathSeparators = [
    " "
    "="
    "<"
    "'"
    "\""
  ];

  # Bashで実行してよいコマンド。
  # 失敗ログやupstreamの文章に仕込まれた指示に従ってしまっても被害を抑えられるよう、
  # 復旧の手順で使うものだけを許可します。
  # `cat`のような読み取り専用のコマンドは、
  # Claude Code自身が作業ディレクトリの中に限って許可するのでここには書きません。
  allowedBashCommands = [
    "./check.sh"
    "diff"
    "gh label list"
    "gh pr checks"
    "gh pr create"
    "gh pr diff"
    "gh pr list"
    "gh pr view"
    "gh repo view"
    "gh run list"
    "gh run view"
    "git add"
    "git cat-file"
    "git checkout"
    "git diff"
    "git fetch"
    "git log"
    "git ls-files"
    "git ls-remote"
    "git merge-base"
    "git restore"
    "git rev-parse"
    "git show"
    "git status"
    "git switch"
    "jq"
    "ls"
    "mkdir"
    "nix build"
    "nix derivation show"
    "nix eval"
    "nix flake lock"
    "nix flake metadata"
    "nix flake prefetch"
    "nix flake show"
    "nix flake update"
    "nix fmt"
    "nix hash"
    "nix log"
    "nix path-info"
    "nix store prefetch-file"
    "nix why-depends"
    "nix-prefetch-url"
    "read-commit-instructions"
    "read-contributing"
    "read-pull-request-template"
    "run-commit-msg-hook"
    "sort"
    "wc"
  ];

  # 許可したコマンドでも塞ぎたい使い方。
  # `deny`は`allow`やスキルの`allowed-tools`より優先されます。
  deniedBashPatterns = [
    # シェルの変数展開とコマンド置換。
    # `gh pr create --body "$GH_TOKEN"`のように、
    # 許可したコマンドの引数を通して環境変数の中身を外へ出せてしまいます。
    "*$*"
    "*`*"
    # jqは`env`と`$ENV`で環境変数を読めます。
    "jq*env*"
    "jq*ENV*"
    # gitの外部コマンドの実行と、作業ツリーの外への書き込み。
    "git*--upload-pack*"
    "git*--receive-pack*"
    "git*--exec*"
    "git*--output*"
    # スキルの`allowed-tools`が許可するもののうち、
    # `prompt.md`の手順と両立しないもの。
    # 署名の無いコミットを積まないよう、
    # ローカルでのコミットとpushは禁止します。
    "git commit*"
    "git push*"
    "sync-and-push*"
    "commit-prepare*"
    "konoka-commit-editor*"
    "konoka-pr-editor*"
    "prepare-editmsg*"
  ]
  ++ lib.concatMap (flag: [
    "nix*${flag}*"
    "./check.sh*${flag}*"
  ]) dangerousNixFlags
  # 環境変数やランナーの秘密が置かれている場所を指す絶対パス。
  # `jq`や`diff`のようにファイルを引数に取るコマンドで読めないようにします。
  # リポジトリにも`home/`があるので、
  # 相対パスと区別できるよう絶対パスの始まりになる区切りの直後だけを対象にします。
  ++ lib.concatMap (dir: map (separator: "*${separator}/${dir}*") absolutePathSeparators) [
    "dev"
    "etc"
    "home"
    "proc"
    "root"
    "run"
    "sys"
    "var"
  ]
  # 作業ツリーの外へ出る相対パス。
  # `../../proc/self/environ`のように上へ辿れば、絶対パスを書かなくても同じ場所を読めます。
  # `git diff a..b`の範囲指定を巻き込まないよう、スラッシュの付いた形と単独の`..`だけを対象にします。
  ++ [
    "*../*"
    "* .."
  ]
  # ホームディレクトリを指すチルダ。
  # `HEAD~1`のようなgitのリビジョン指定を巻き込まないよう、
  # 絶対パスと同じ区切りの直後だけを対象にします。
  ++ map (separator: "*${separator}~*") absolutePathSeparators;

  # 普段の`home/core/claude-code.nix`の設定から、
  # ランナーでも意味のあるものだけを抜き出しています。
  #
  # `permissions`は実行ごとに変わらないものだけをここに書きます。
  # リポジトリ名やPRの番号、
  # `runner.temp`のパスに依存するものはワークフローの`claude_args`で足します。
  settings = writeText "settings.json" (
    builtins.toJSON {
      language = "japanese";
      attribution = {
        commit = "";
        pr = "";
        sessionUrl = false;
      };
      permissions = {
        disableBypassPermissionsMode = "disable";
        allow = [
          # 作業ツリーへの書き込み。
          # 作業ディレクトリと`--add-dir`の外は許可しません。
          # ファイルの権限の判定には`Edit`と`Read`の規則だけが使われ、
          # `Edit`は`Write`などの書き込む全てのツールに、
          # `Read`は`Glob`や`Grep`などの読む全てのツールに効きます。
          "Edit(./**)"
          # 依存のソースを調べるための読み取り。
          "Read(//nix/store/**)"
          "Agent"
          "Skill"
          "TodoWrite"
          # `WebFetch`は直接は許可しません。
          # 取得したページの内容は外部の文章で指示を仕込まれやすく、
          # URLに値を埋めて外へ送ることもできるからです。
          # 外部の情報は`research`スキルで調べさせます。
          # `research:survey`スキルは`allowed-tools`で`WebFetch`を許可しているので、
          # 独立したサブエージェントの中でだけ使えます。
          # 調べた結果は要約として戻るので、
          # ページの文章がそのままメインの文脈に入ることも避けられます。
          "WebSearch"
          "mcp__github_file_ops__commit_files"
          "mcp__github_file_ops__delete_files"
          "mcp__plugin_nix-tasuke_nixos"
          "mcp__plugin_research_cloudflare"
          "mcp__plugin_research_context7"
          "mcp__plugin_research_deepwiki"
          "mcp__plugin_research_mdn"
          "mcp__plugin_research_microsoft-learn"
        ]
        ++ map (command: "Bash(${command}:*)") allowedBashCommands;
        deny = [
          # gitの設定を書き換えると、
          # `git diff`などに任意のコマンドを実行させられます。
          "Edit(./.git/**)"
          # `./check.sh`は許可しているので、中身を書き換えられると任意のコマンドを実行できます。
          "Edit(./check.sh)"
          # 渡されているトークンでは変更をコミットできません。
          "Edit(./.github/workflows/**)"
          # スキルの`allowed-tools`は範囲の無い`Edit`を許可することがあり、
          # そのスキルが動いている間は作業ツリーの外にも書けてしまいます。
          # ホームディレクトリのシェルの設定などと、
          # 同じコンテナで動く全てのランナーの`runner.temp`への書き込みを拒否します。
          # `runner.temp`には後のステップが使うスクリプトのコピーや`GITHUB_ENV`のファイルがあります。
          "Edit(~/**)"
          "Edit(//run/github-runner/*/_temp/**)"
          "Read(//proc/**)"
        ]
        ++ map (pattern: "Bash(${pattern})") deniedBashPatterns;
      };
    }
  );
in
runCommand "renovate-recovery-claude-config" { } ''
  mkdir -p $out/plugins $out/git-hooks
  ${lib.concatStrings (
    lib.mapAttrsToList (name: plugin: ''
      ln -s ${plugin} $out/plugins/${name}
    '') plugins
  )}
  # 他のフックはgit-lfsへの委譲やブランチの削除なので、
  # コミットメッセージの検査だけを使います。
  ln -s ${git-hooks}/lib/git-hooks/dist/hooks/commit-msg $out/git-hooks/commit-msg
  ln -s ${appendSystemPrompt} $out/append-system-prompt.md
  ln -s ${settings} $out/settings.json
''
