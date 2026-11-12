# RenovateのPRのCIが失敗した時に、Claude Codeを起動するかどうかを決めて、結果をPRへ記録するスクリプト。
#
# `.github/workflows/renovate-recovery.yml`が`actions/github-script`から`src/gate.ts`などを読み込む。
# このderivationはリントと型検査とテストをCIで走らせるためのもので、それ自体の成果物は無い。
# `passthru`の`tools`と`nodeModules`は、
# `renovate-recovery-claude-config`のビルドの中で`tools/`の検査を動かすために使う。
# Claude Codeへの指示は`prompt.md`にある。
#
# 補助プログラムの言語の基準ではHaskellになるが、TypeScriptで書いている。
# `src/`は、github-scriptが認証済みのoctokitのクライアントと実行の文脈を注入してくれるので、
# GitHubのAPIを呼ぶ処理をビルドも依存のインストールも無しに書けるため。
# `tools/`はgithub-scriptを通さないが、
# 同じパッケージの型検査とリントとvitestをそのまま使え、
# YAMLのfrontmatterを`yaml`で読めるので、言語を混ぜずにTypeScriptにしている。
#
# `package.json`の依存は全て開発用で、実行時には何もインストールされない。
# `src/`から型以外をimportしてよいのはNode.jsの組み込みモジュールだけ。
# `tools/`はビルドの中でnode_modulesと一緒に動かすスクリプトで、依存をimportしてよい。
{
  lib,
  runCommand,
  nodejs,
  importNpmLock,
}:
let
  npmRoot = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
    ];
  };
  nodeModules = importNpmLock.buildNodeModules {
    inherit nodejs npmRoot;
  };
  tsRoot = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./package-lock.json
      ./.gitignore
      ./eslint.config.ts
      ./tsconfig.json
      ./vitest.config.ts
      ./src
      ./test
      ./tools
    ];
  };
in
runCommand "renovate-recovery"
  {
    nativeBuildInputs = [ nodejs ];
    # `tools/`のスクリプトを他のderivationの中で動かすために出します。
    passthru = {
      inherit nodeModules;
      tools = lib.fileset.toSource {
        root = ./.;
        fileset = ./tools;
      };
    };
  }
  ''
    cp -r ${tsRoot}/. .
    ln -s ${nodeModules}/node_modules node_modules
    npm run lint
    npm run test
    touch $out
  ''
