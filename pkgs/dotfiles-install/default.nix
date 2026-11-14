# このdotfilesの設定を、今の環境に合ったコマンドで適用するコマンド。
#
# リポジトリルートの`install.sh`が`nix run .#dotfiles-install`で呼ぶ。
# `install.sh`はまだ何も入っていない環境からここへ辿り着くための入口で、
# 環境の判別や`last-commit.json`の注入のような処理は全てこちらに置く。
#
# Gitの操作は`git`コマンドに任せるので、PATHへ足して包む。
# `sudo`や`nixos-rebuild`のような適用のコマンドは、
# 利用者の環境に入っているものを使うので包まない。
#
# `callPackage`の結果に`haskell.lib`の関数を重ねると、
# `override`がこのファイルを`mkDerivation`付きで呼び直して壊れる。
# CIで警告をエラーにしたい時は`werror`で指定する。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  git,
  himari-src,
  werror ? false,
}:
let
  packages = haskellPackages.extend (
    hself: _hsuper: {
      # himariはstableのnixpkgsではbrokenなので、上流のソースから組む。
      himari = hself.callCabal2nix "himari" himari-src { };
    }
  );
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
  package = packages.callCabal2nix "dotfiles-install" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # テストは一時ディレクトリに実際のリポジトリを作って確かめる。
    testToolDepends = (old.testToolDepends or [ ]) ++ [ git ];
    # 利用者の環境にgitがあればそちらを優先するので、後ろへ足す。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/dotfiles-install" \
        --suffix PATH : ${lib.makeBinPath [ git ]}
    '';
  }))
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  haskell.lib.compose.justStaticExecutables
]
