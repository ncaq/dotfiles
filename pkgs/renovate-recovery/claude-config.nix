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
  writeShellApplication,
  gawk,
  gnused,
  yq-go,
  konokaPlugins,
  git-hooks,
}:
let
  # スキルの`allowed-tools`が範囲の無い`Bash`を許可していないかを確かめるコマンド。
  # YAMLを読む処理はyqに任せていて、
  # ビルドの中で一度走るだけの検査なのでシェルスクリプトにしています。
  checkSkillAllowedTools = writeShellApplication {
    name = "check-skill-allowed-tools";
    runtimeInputs = [
      gawk
      gnused
      yq-go
    ];
    text = builtins.readFile ./check-skill-allowed-tools.sh;
  };
  # 検査そのものが期待どおりに判定するかを確かめるための固定のSKILL.md。
  # `unrestricted`は検出されるべきもの、`restricted`は検出されてはいけないものです。
  skillFixtures = ./test/skill-allowed-tools;

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
    # ビルド結果へのシンボリックリンクを任意の場所に作るオプション。
    # ストアのパス自体が作業ツリーの外を指すリンクになりうるので、
    # 作業ツリーに外へのリンクを置けてしまいます。
    # `-o`は値を続けて書けるので、空白の直後の`-o`で塞ぎます。
    "--out-link"
    " -o"
    "--profile"
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
  # `jq`や`sort`や`diff`や`wc`のように任意のファイルを引数に取るコマンドもここには書きません。
  # ここで許可すると前置きの照合だけで通り、
  # 下の拒否の規則をglobなどで迂回して作業ツリーの外を読めてしまいます。
  # 書かなければClaude Code自身の検査を通り、
  # globを含めて作業ディレクトリの外のパスを拒否してくれます。
  allowedBashCommands = [
    "./check.sh"
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
    "ls"
    "mkdir"
    # `--no-link`が無いと作業ツリーに`result`のリンクを作ります。
    # derivationの出力は作業ツリーの外を指すリンクにもなれるので、
    # 許可したコマンドにそのリンクを渡すと外のファイルを読めてしまいます。
    "nix build --no-link"
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
  ];

  # 許可したコマンドでも塞ぎたい使い方。
  # `deny`は`allow`やスキルの`allowed-tools`より優先されます。
  deniedBashPatterns = [
    # シェルの変数展開とコマンド置換。
    # `gh pr create --body "$GH_TOKEN"`のように、
    # 許可したコマンドの引数を通して環境変数の中身を外へ出せてしまいます。
    "*$*"
    "*`*"
    # シェルのglobとブレース展開。
    # 規則が照合した後でシェルが展開するので、
    # `/pr?c/self/environ`のように書くと絶対パスの拒否を迂回できます。
    # `*`も同じように使えますが、規則の文法で`*`そのものを指せないので塞げていません。
    "*?*"
    "*[*"
    "*{*"
    # ファイルを読み込むコマンドに絶対パスを渡すこと。
    # ストアのパスはderivationの作り方次第で`/proc/self/environ`などへのリンクにできるので、
    # `/nix/store`の下を指していても外のファイルを読めます。
    # `Read`ツールはリンクを解決して拒否しますが、Bashのコマンドはたどってしまいます。
    # スキルの`allowed-tools`も`run-commit-msg-hook`を範囲を絞らず許可するので、
    # 許可の一覧ではなく拒否で塞ぎます。
    "run-commit-msg-hook /*"
    "gh*--body-file /*"
    "gh*--body-file=/*"
    "gh* -F /*"
    "gh* -F/*"
    # 入力のリダイレクトで同じように外のファイルを読ませること。
    "*<*"
    # jqは許可していませんが、
    # スキルの`allowed-tools`が許可した時に備えて、
    # `env`と`$ENV`で環境変数を読む使い方を拒否します。
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
          # 作業ツリーの外への書き込みは許可しません。
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
          # 取得したページの文章には指示を仕込まれやすいので、
          # メインの文脈にそのまま入れないためです。
          # 外部の情報は`research`スキルで調べさせます。
          # `research:survey`スキルは`allowed-tools`で`WebFetch`を許可しているので、
          # 独立したサブエージェントの中でだけ使えて、
          # 結果は要約として戻ります。
          #
          # URLに値を埋めて外へ送ることは、
          # これだけでは防げません。
          # `git fetch`や`nix-prefetch-url`などの許可したコマンドも任意のURLへ届きます。
          # ハッシュの更新などで任意のURLが要るので、これらの行き先は絞りません。
          # 変数展開とコマンド置換は拒否しているので、
          # 送るには読んだ値をコマンドへ直接書き写す必要があります。
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

  # 上流の構成が変わってもビルドが通ってしまい、
  # 復旧が必要になった時に初めて壊れていたと気付く事態を避けるため、
  # 前提が崩れていたらここで失敗させます。
  # `ln -s`はリンク先が無くても成功するので、リンク先を確かめます。
  if [ ! -x $out/git-hooks/commit-msg ]; then
    echo "git-hooksのcommit-msgフックが見つかりません" >&2
    exit 1
  fi
  for plugin in $out/plugins/*; do
    if [ ! -f "$plugin/.claude-plugin/plugin.json" ]; then
      echo "$plugin はClaude Codeのプラグインではありません" >&2
      exit 1
    fi
  done

  # konokaの更新で範囲の無い`Bash`を許可するスキルが入ったら気付けるようにします。
  # 検査が壊れて何も検出しなくなっても気付けるよう、
  # 先に固定のSKILL.mdで判定が期待どおりかを確かめます。
  for skill in ${skillFixtures}/unrestricted/*/SKILL.md; do
    if ${lib.getExe checkSkillAllowedTools} "$skill" 2>/dev/null; then
      echo "検査が $skill を見逃しました" >&2
      exit 1
    fi
  done
  ${lib.getExe checkSkillAllowedTools} ${skillFixtures}/restricted/*/SKILL.md
  shopt -s nullglob
  ${lib.getExe checkSkillAllowedTools} $out/plugins/*/skills/*/SKILL.md
''
