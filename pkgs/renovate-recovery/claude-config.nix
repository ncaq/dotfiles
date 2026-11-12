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
  #
  # `commit`と`pr`は、
  # `commit-style`と`pr-style`のスタイルの規則と、
  # `run-commit-msg-hook`によるコミットメッセージの検査のために読み込みます。
  # コミットとPRの作成そのものは`prompt.md`の手順で行います。
  pluginNames = [
    "commit"
    "haskell-tasuke"
    "log-analyzer"
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

  # 普段の`home/core/claude-code.nix`の設定から、
  # ランナーでも意味のあるものだけを抜き出しています。
  settings = writeText "settings.json" (
    builtins.toJSON {
      language = "japanese";
      attribution = {
        commit = "";
        pr = "";
        sessionUrl = false;
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
