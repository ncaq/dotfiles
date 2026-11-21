# Gitリポジトリをcloneして、安全な時だけfast-forwardで更新するコマンド。
#
# `lib/git-repo-subscribe.nix`のhome-managerモジュールが、
# 購読するリポジトリごとに呼ぶ。
# Gitの操作は`git`コマンドに任せるので、PATHへ足して包む。
{
  lib,
  haskell,
  localHaskellPackages,
  makeWrapper,
  git,
}:
let
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
  package = localHaskellPackages.callCabal2nix "git-repo-subscribe" source { };
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
  haskell.lib.compose.justStaticExecutables
]
