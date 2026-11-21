# GitHub Actionsのランナの登録トークンを発行してファイルに置くコマンド。
#
# seminarのランナの隔離環境ごとのサービスから呼ばれる。
# 何をするかは`src/GithubRunnerRegistrationToken/Cli.hs`に、
# 入力の環境変数は`src/GithubRunnerRegistrationToken/Config.hs`に書いてある。
#
# GitHubのAPIは自前でHTTPを叩くので、外部コマンドへの依存は無い。
{
  lib,
  haskell,
  localHaskellPackages,
}:
let
  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すと`dist-newstyle`のような作業中のファイルまで付いてくる。
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./github-runner-registration-token.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = localHaskellPackages.callCabal2nix "github-runner-registration-token" source { };
in
lib.pipe package [
  # seminarのクロージャへGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
