# Gitリポジトリをcloneして、安全な時だけfast-forwardで更新するコマンド。
#
# `lib/git-repo-subscribe.nix`のhome-managerモジュールが、
# 購読するリポジトリごとに呼ぶ。
# Gitの操作は`git`コマンドに任せるので、PATHへ足して包む。
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
      ./git-repo-subscribe.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "git-repo-subscribe" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # テストは一時ディレクトリに実際のリポジトリを作って確かめる。
    testToolDepends = (old.testToolDepends or [ ]) ++ [ git ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/git-repo-subscribe" \
        --prefix PATH : ${lib.makeBinPath [ git ]}
    '';
  }))
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  haskell.lib.compose.justStaticExecutables
]
