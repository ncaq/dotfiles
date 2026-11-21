# このdotfilesの設定を、今の環境に合ったコマンドで適用するコマンド。
#
# リポジトリルートの`install.sh`が`nix run .#dotfiles-install`で呼ぶ。
# `install.sh`はまだ何も入っていない環境からここへ辿り着くための入口で、
# 環境の判別や`last-commit.json`の注入のような処理は全てこちらに置く。
#
# Gitの操作は`git`コマンドに任せるので、PATHへ足して包む。
# `sudo`や`nixos-rebuild`のような適用のコマンドは、
# 利用者の環境に入っているものを使うので包まない。
# `home-manager`だけは、最初の適用の時にはまだどこにも入っていないので足す。
{
  lib,
  haskell,
  localHaskellPackages,
  makeWrapper,
  git,
  home-manager,
}:
let
  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すと`dist-newstyle`のような作業中のファイルまで付いてくる。
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./dotfiles-install.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = localHaskellPackages.callCabal2nix "dotfiles-install" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # テストは一時ディレクトリに実際のリポジトリを作って確かめる。
    testToolDepends = (old.testToolDepends or [ ]) ++ [ git ];
    # 利用者の環境にgitやhome-managerがあればそちらを優先するので、後ろへ足す。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/dotfiles-install" \
        --suffix PATH : ${
          lib.makeBinPath [
            git
            home-manager
          ]
        }
    '';
  }))
  haskell.lib.compose.justStaticExecutables
]
