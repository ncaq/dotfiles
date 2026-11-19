# flakeに定義された全ホストのクロージャをGC rootとして登録するコマンド。
#
# `nixos/host/seminar/nix-gc-root-hosts.nix`のサービスから呼ばれる。
# 何をどう登録するかは`src/NixGcRootHosts/Register.hs`に書いてある。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  nix,
  himari-src,
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
  haskell.lib.compose.justStaticExecutables
]
