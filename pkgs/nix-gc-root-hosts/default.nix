# flakeに定義された全ホストの閉包をGC rootとして登録するコマンド。
#
# `nixos/host/seminar/nix-gc-root-hosts.nix`のサービスから呼ばれる。
# 何をどう登録するかは`src/NixGcRootHosts/Register.hs`に書いてある。
#
# `callPackage`の結果に`haskell.lib`の関数を重ねると、
# `override`がこのファイルを`mkDerivation`付きで呼び直して壊れる。
# CIで警告をエラーにしたい時は`werror`で指定する。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  nix,
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
      ./nix-gc-root-hosts.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "nix-gc-root-hosts" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # 構成の列挙とビルドは`nix`に任せるので、PATHへ足して包む。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/nix-gc-root-hosts" \
        --prefix PATH : ${lib.makeBinPath [ nix ]}
    '';
  }))
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  haskell.lib.compose.justStaticExecutables
]
