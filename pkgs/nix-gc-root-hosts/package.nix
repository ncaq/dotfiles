# flakeに定義された全ホストのクロージャをGC rootとして登録するコマンド。
#
# 同じディレクトリの`module.nix`が定義する`nix-gc-root-hosts.service`から呼ばれる。
# 何をどう登録するかは`src/NixGcRootHosts/Register.hs`に書いてある。
{
  lib,
  haskell,
  localHaskellPackages,
  makeWrapper,
  nix,
  localLib,
  testers,
}:
let
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
  package = localHaskellPackages.callCabal2nix "nix-gc-root-hosts" source { };
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
  # GCの前に挟まる順序はユニットの組み合わせで決まるので、コンテナの中で実際のユニットを読み込んで確かめる。
  # 配るもののstoreパスに関わらないように、`checkPhase`ではなく`passthru.tests`に置く。
  (
    package:
    package.overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        tests = (old.passthru.tests or { }) // {
          nixos = import ./nixos-test.nix { inherit localLib testers; };
        };
      };
    })
  )
]
